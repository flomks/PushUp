import AuthenticationServices
import CryptoKit
import Foundation
import ObjectiveC
import UIKit

enum SpotifyDestination: Equatable {
    case app(URL)
    case web(URL)

    var url: URL {
        switch self {
        case .app(let url), .web(let url):
            return url
        }
    }
}

enum SpotifyConnectResult: Equatable {
    case connected
    case openedExternal
    case unavailable(String)
}

private struct SpotifyTokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct SpotifySession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let scope: String
}

@MainActor
final class SpotifyService: NSObject {

    static let shared = SpotifyService()

    private enum Keys {
        static let session = "spotify.session"
    }

    private let userDefaults: UserDefaults
    private var webAuthSession: ASWebAuthenticationSession?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        super.init()
    }

    var isConfigured: Bool {
        !(spotifyClientID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func isSpotifyAppInstalled() -> Bool {
        guard let url = URL(string: "spotify://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func hasValidSession() -> Bool {
        guard let session = loadSession() else { return false }
        return session.expiresAt.timeIntervalSinceNow > 60
    }

    @discardableResult
    func connect() async -> SpotifyConnectResult {
        if hasValidSession() {
            return .connected
        }

        if let refreshed = await refreshIfNeeded(), refreshed {
            return .connected
        }

        guard isConfigured else {
            return openConnectDestination()
                ? .openedExternal
                : .unavailable("Spotify is not configured in Info.plist.")
        }

        do {
            let callbackURL = try await startAuthorizationSession()
            let session = try await exchangeAuthorizationCode(callbackURL: callbackURL)
            saveSession(session)
            return .connected
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    @discardableResult
    func openConnectDestination() -> Bool {
        open(Self.connectDestination(isSpotifyInstalled: isSpotifyAppInstalled()))
    }

    @discardableResult
    func openModePreset(_ mode: RunAudioMode) -> Bool {
        open(Self.modeDestination(mode: mode, isSpotifyInstalled: isSpotifyAppInstalled()))
    }

    @discardableResult
    func openTrack(_ track: RunTrack) -> Bool {
        open(Self.trackDestination(track: track, isSpotifyInstalled: isSpotifyAppInstalled()))
    }

    func disconnect() {
        userDefaults.removeObject(forKey: Keys.session)
    }

    private var spotifyClientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String
    }

    private var redirectURI: String? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return "\(bundleID)://spotify-auth"
    }

    private func loadSession() -> SpotifySession? {
        guard let data = userDefaults.data(forKey: Keys.session) else { return nil }
        return try? JSONDecoder().decode(SpotifySession.self, from: data)
    }

    private func saveSession(_ session: SpotifySession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        userDefaults.set(data, forKey: Keys.session)
    }

    private func open(_ destination: SpotifyDestination) -> Bool {
        let url = destination.url
        switch destination {
        case .app:
            guard UIApplication.shared.canOpenURL(url) else { return false }
            UIApplication.shared.open(url)
            return true
        case .web:
            UIApplication.shared.open(url)
            return true
        }
    }

    private func startAuthorizationSession() async throws -> URL {
        guard let clientID = spotifyClientID, !clientID.isEmpty else {
            throw NSError(domain: "SpotifyService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing SpotifyClientID."])
        }
        guard let redirectURI else {
            throw NSError(domain: "SpotifyService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing bundle identifier for Spotify redirect URI."])
        }

        let verifier = Self.generateCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.scopes),
        ]

        objc_setAssociatedObject(self, &AssociatedKeys.pkceVerifier, verifier, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        let callbackURL = try await openWebAuthSession(
            url: components.url!,
            callbackScheme: Bundle.main.bundleIdentifier ?? ""
        )
        return callbackURL
    }

    private func exchangeAuthorizationCode(callbackURL: URL) async throws -> SpotifySession {
        let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            throw NSError(domain: "SpotifyService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Spotify auth failed: \(error)"])
        }

        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw NSError(domain: "SpotifyService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Spotify callback missing authorization code."])
        }

        guard let clientID = spotifyClientID, let redirectURI else {
            throw NSError(domain: "SpotifyService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Spotify configuration became unavailable."])
        }

        guard let verifier = objc_getAssociatedObject(self, &AssociatedKeys.pkceVerifier) as? String else {
            throw NSError(domain: "SpotifyService", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing PKCE verifier for Spotify exchange."])
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown response"
            throw NSError(domain: "SpotifyService", code: 7, userInfo: [NSLocalizedDescriptionKey: "Spotify token exchange failed: \(body)"])
        }

        let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        return SpotifySession(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            scope: token.scope
        )
    }

    private func refreshIfNeeded() async -> Bool? {
        guard let session = loadSession(), let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            return nil
        }
        guard session.expiresAt.timeIntervalSinceNow <= 60 else {
            return true
        }
        guard let clientID = spotifyClientID else { return nil }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            saveSession(
                SpotifySession(
                    accessToken: token.accessToken,
                    refreshToken: token.refreshToken ?? refreshToken,
                    expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                    scope: token.scope
                )
            )
            return true
        } catch {
            return nil
        }
    }

    private func openWebAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        guard
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first
        else {
            throw NSError(domain: "SpotifyService", code: 8, userInfo: [NSLocalizedDescriptionKey: "No active window found for Spotify authentication."])
        }

        let provider = WebAuthPresentationProvider(window: keyWindow)

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                self?.webAuthSession = nil
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: NSError(domain: "SpotifyService", code: 9, userInfo: [NSLocalizedDescriptionKey: "No Spotify callback URL returned."]))
                }
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = provider
            self.webAuthSession = session
            session.start()
        }
    }

    static func connectDestination(isSpotifyInstalled: Bool) -> SpotifyDestination {
        if isSpotifyInstalled, let url = URL(string: "spotify://") {
            return .app(url)
        }
        return .web(URL(string: "https://open.spotify.com/")!)
    }

    static func modeDestination(mode: RunAudioMode, isSpotifyInstalled: Bool) -> SpotifyDestination {
        searchDestination(query: mode.searchQuery, isSpotifyInstalled: isSpotifyInstalled)
    }

    static func trackDestination(track: RunTrack, isSpotifyInstalled: Bool) -> SpotifyDestination {
        searchDestination(query: "\(track.title) \(track.artist)", isSpotifyInstalled: isSpotifyInstalled)
    }

    private static func searchDestination(query: String, isSpotifyInstalled: Bool) -> SpotifyDestination {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if isSpotifyInstalled, let appURL = URL(string: "spotify://search?query=\(encodedQuery)") {
            return .app(appURL)
        }
        return .web(URL(string: "https://open.spotify.com/search/\(encodedQuery)")!)
    }

    private static func generateCodeVerifier() -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return String((0..<96).compactMap { _ in chars.randomElement() })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func formBody(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static let scopes = [
        "user-read-private",
        "user-read-email",
        "user-read-playback-state",
        "user-modify-playback-state",
    ].joined(separator: " ")
}

private enum AssociatedKeys {
    static var pkceVerifier: UInt8 = 0
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension RunAudioMode {
    var searchQuery: String {
        switch self {
        case .recovery:
            return "recovery run playlist"
        case .base:
            return "base run playlist"
        case .tempo:
            return "tempo run playlist"
        case .longRun:
            return "long run playlist"
        case .race:
            return "race pace playlist"
        }
    }
}

private final class WebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: UIWindow

    init(window: UIWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}
