import Combine
import CoreLocation
import Foundation
import AuthenticationServices
import CryptoKit
import ObjectiveC
import Shared
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

struct SpotifyProfile: Equatable {
    let displayName: String
    let product: String
}

struct SpotifyPlaybackSnapshot: Equatable {
    let trackTitle: String
    let artistName: String
    let isPlaying: Bool
    let deviceName: String?
}

private struct SpotifyProfileResponse: Decodable {
    let displayName: String?
    let product: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case product
    }
}

private struct SpotifyPlaybackResponse: Decodable {
    let isPlaying: Bool
    let item: SpotifyTrackResponse?
    let device: SpotifyDeviceResponse?

    enum CodingKeys: String, CodingKey {
        case isPlaying = "is_playing"
        case item
        case device
    }
}

private struct SpotifyTrackResponse: Decodable {
    let name: String
    let uri: String?
    let artists: [SpotifyArtistResponse]

    enum CodingKeys: String, CodingKey {
        case name, uri, artists
    }
}

private struct SpotifyArtistResponse: Decodable {
    let name: String
}

private struct SpotifyDeviceResponse: Decodable {
    let id: String?
    let name: String
    let isActive: Bool
    let isRestricted: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isActive = "is_active"
        case isRestricted = "is_restricted"
    }
}

private struct SpotifyAvailableDevicesResponse: Decodable {
    let devices: [SpotifyDeviceResponse]
}

// MARK: - Recommendations API Response

private struct SpotifyRecommendationsResponse: Decodable {
    let tracks: [SpotifyRecommendedTrack]
}

private struct SpotifyRecommendedTrack: Decodable {
    let name: String
    let uri: String
    let artists: [SpotifyArtistResponse]

    enum CodingKeys: String, CodingKey {
        case name, uri, artists
    }
}

private struct SpotifyTopTracksResponse: Decodable {
    let items: [SpotifyTopTrackItem]
}

private struct SpotifyTopTrackItem: Decodable {
    let id: String
}

/// A real Spotify track fetched from the Recommendations API.
struct SpotifyRecommendedRunTrack: Identifiable, Equatable {
    let id: String          // Spotify URI
    let title: String
    let artist: String
    let uri: String
}

/// Audio parameters for each RunAudioMode used to query Spotify recommendations.
struct RunModeAudioParams {
    let minTempo: Double
    let maxTempo: Double
    let targetTempo: Double
    let targetEnergy: Double
    let targetValence: Double
    let genreSeeds: [String]

    static func params(for mode: RunAudioMode) -> RunModeAudioParams {
        switch mode {
        case .recovery:
            return RunModeAudioParams(minTempo: 105, maxTempo: 125, targetTempo: 115, targetEnergy: 0.3, targetValence: 0.4, genreSeeds: ["acoustic", "ambient", "chill", "pop"])
        case .base:
            return RunModeAudioParams(minTempo: 150, maxTempo: 168, targetTempo: 160, targetEnergy: 0.6, targetValence: 0.5, genreSeeds: ["dance", "house", "pop", "electro"])
        case .tempo:
            return RunModeAudioParams(minTempo: 168, maxTempo: 185, targetTempo: 175, targetEnergy: 0.8, targetValence: 0.6, genreSeeds: ["edm", "dance", "electro", "techno"])
        case .longRun:
            return RunModeAudioParams(minTempo: 140, maxTempo: 158, targetTempo: 150, targetEnergy: 0.5, targetValence: 0.5, genreSeeds: ["rock", "indie", "pop", "alt-rock"])
        case .race:
            return RunModeAudioParams(minTempo: 178, maxTempo: 195, targetTempo: 185, targetEnergy: 0.9, targetValence: 0.7, genreSeeds: ["edm", "techno", "rock", "electro"])
        }
    }
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

    var sessionStatusDescription: String {
        guard let session = loadSession() else {
            return isSpotifyAppInstalled() ? "Spotify app installed, not authenticated" : "Spotify web fallback only"
        }
        let remainingMinutes = max(Int(session.expiresAt.timeIntervalSinceNow / 60), 0)
        return "Authenticated, expires in ~\(remainingMinutes)m"
    }

    func fetchProfile() async throws -> SpotifyProfile {
        let request = try await authorizedRequest(path: "/v1/me")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let payload = try JSONDecoder().decode(SpotifyProfileResponse.self, from: data)
        return SpotifyProfile(
            displayName: payload.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Spotify User",
            product: payload.product?.capitalized ?? "Unknown"
        )
    }

    func fetchPlaybackState() async throws -> SpotifyPlaybackSnapshot? {
        let request = try await authorizedRequest(path: "/v1/me/player")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "SpotifyService", code: 10, userInfo: [NSLocalizedDescriptionKey: "Invalid Spotify response."])
        }
        if http.statusCode == 204 {
            return nil
        }
        try validate(response: response, data: data)
        let payload = try JSONDecoder().decode(SpotifyPlaybackResponse.self, from: data)
        guard let item = payload.item else { return nil }
        return SpotifyPlaybackSnapshot(
            trackTitle: item.name,
            artistName: item.artists.map(\.name).joined(separator: ", "),
            isPlaying: payload.isPlaying,
            deviceName: payload.device?.name
        )
    }

    // MARK: - Recommendations API

    /// Fetches the user's top track IDs to use as seeds for recommendations.
    private func fetchSeedTrackIDs(limit: Int = 5) async throws -> [String] {
        let request = try await authorizedRequest(path: "/v1/me/top/tracks?limit=\(limit)&time_range=short_term")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }
        let payload = try JSONDecoder().decode(SpotifyTopTracksResponse.self, from: data)
        return payload.items.map(\.id)
    }

    /// Fetches recommended tracks from Spotify based on the given audio parameters.
    func fetchRecommendations(params: RunModeAudioParams, limit: Int = 20) async throws -> [SpotifyRecommendedRunTrack] {
        let trackSeeds = Array(try await fetchSeedTrackIDs(limit: 10).shuffled().prefix(2))
        let primaryGenres = Array(params.genreSeeds.shuffled().prefix(trackSeeds.isEmpty ? 2 : 1))
        let variants = [
            recommendationQueryItems(
                params: params,
                limit: limit,
                trackSeeds: trackSeeds,
                genreSeeds: primaryGenres
            ),
            recommendationQueryItems(
                params: params,
                limit: limit,
                trackSeeds: [],
                genreSeeds: params.genreSeeds,
                includeTempoBounds: false
            ),
            recommendationQueryItems(
                params: params,
                limit: limit,
                trackSeeds: [],
                genreSeeds: ["pop"],
                includeTempoBounds: false,
                includeMoodTargets: false
            )
        ]

        var lastError: Error?

        for queryItems in variants {
            do {
                let payload = try await fetchRecommendations(queryItems: queryItems)
                let mapped = payload.tracks.map { track in
                    SpotifyRecommendedRunTrack(
                        id: track.uri,
                        title: track.name,
                        artist: track.artists.map(\.name).joined(separator: ", "),
                        uri: track.uri
                    )
                }
                let deduplicated = Array(Dictionary(grouping: mapped, by: \.uri).compactMap { $0.value.first }).shuffled()
                if !deduplicated.isEmpty {
                    return deduplicated
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(
            domain: "SpotifyService",
            code: 26,
            userInfo: [NSLocalizedDescriptionKey: "Spotify returned no matching tracks for this run mode."]
        )
    }

    /// Starts playback of a specific track URI on the user's active device.
    func playTrack(uri: String) async throws {
        let deviceID = try await ensurePlaybackDevice()
        var request = try await authorizedRequest(path: "/v1/me/player/play?device_id=\(deviceID)")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["uris": [uri]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) || http.statusCode == 204 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SpotifyService", code: 24, userInfo: [NSLocalizedDescriptionKey: "Play track failed: \(msg)"])
        }
    }

    /// Queues a track URI to play next.
    func addToQueue(uri: String) async throws {
        let encoded = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uri
        let deviceID = try await ensurePlaybackDevice()
        var request = try await authorizedRequest(path: "/v1/me/player/queue?uri=\(encoded)&device_id=\(deviceID)")
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) || http.statusCode == 204 else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SpotifyService", code: 25, userInfo: [NSLocalizedDescriptionKey: "Queue failed: \(msg)"])
        }
    }

    private func fetchAvailableDevices() async throws -> [SpotifyDeviceResponse] {
        let request = try await authorizedRequest(path: "/v1/me/player/devices")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let payload = try JSONDecoder().decode(SpotifyAvailableDevicesResponse.self, from: data)
        return payload.devices
    }

    private func transferPlayback(to deviceID: String, play: Bool) async throws {
        var request = try await authorizedRequest(path: "/v1/me/player")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "device_ids": [deviceID],
            "play": play
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) || http.statusCode == 204 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SpotifyService", code: 28, userInfo: [NSLocalizedDescriptionKey: "Transfer playback failed: \(body)"])
        }
    }

    private func ensurePlaybackDevice() async throws -> String {
        let devices = try await fetchAvailableDevices()

        if let active = devices.first(where: { $0.isActive && !($0.isRestricted ?? false) }),
           let deviceID = active.id,
           !deviceID.isEmpty {
            return deviceID
        }

        if let candidate = devices.first(where: { !($0.isRestricted ?? false) }),
           let deviceID = candidate.id,
           !deviceID.isEmpty {
            try await transferPlayback(to: deviceID, play: false)
            return deviceID
        }

        throw NSError(
            domain: "SpotifyService",
            code: 29,
            userInfo: [NSLocalizedDescriptionKey: "No Spotify playback device is available. Open Spotify on your phone or another device first."]
        )
    }

    // MARK: - Playback Controls (Web API)

    func skipToNext() async throws {
        var request = try await authorizedRequest(path: "/v1/me/player/next")
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) || http.statusCode == 204 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SpotifyService", code: 20, userInfo: [NSLocalizedDescriptionKey: "Skip failed: \(body)"])
        }
    }

    func skipToPrevious() async throws {
        var request = try await authorizedRequest(path: "/v1/me/player/previous")
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) || http.statusCode == 204 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SpotifyService", code: 21, userInfo: [NSLocalizedDescriptionKey: "Previous failed: \(body)"])
        }
    }

    func resumePlayback() async throws {
        var request = try await authorizedRequest(path: "/v1/me/player/play")
        request.httpMethod = "PUT"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) || http.statusCode == 204 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SpotifyService", code: 22, userInfo: [NSLocalizedDescriptionKey: "Resume failed: \(body)"])
        }
    }

    func pausePlayback() async throws {
        var request = try await authorizedRequest(path: "/v1/me/player/pause")
        request.httpMethod = "PUT"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) || http.statusCode == 204 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SpotifyService", code: 23, userInfo: [NSLocalizedDescriptionKey: "Pause failed: \(body)"])
        }
    }

    private var spotifyClientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String
    }

    private var redirectURI: String? {
        "pushup-spotify://callback"
    }

    private func loadSession() -> SpotifySession? {
        guard let data = userDefaults.data(forKey: Keys.session) else { return nil }
        return try? JSONDecoder().decode(SpotifySession.self, from: data)
    }

    private func saveSession(_ session: SpotifySession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        userDefaults.set(data, forKey: Keys.session)
    }

    private func callbackScheme() -> String {
        URL(string: redirectURI ?? "")?.scheme ?? "pushup-spotify"
    }

    private func authorizedRequest(path: String) async throws -> URLRequest {
        if let refreshed = await refreshIfNeeded(), !refreshed {
            throw NSError(domain: "SpotifyService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Spotify session refresh failed."])
        }
        guard let session = loadSession() else {
            throw NSError(domain: "SpotifyService", code: 12, userInfo: [NSLocalizedDescriptionKey: "No Spotify session available."])
        }
        var request = URLRequest(url: URL(string: "https://api.spotify.com\(path)")!)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown response"
            throw NSError(domain: "SpotifyService", code: 13, userInfo: [NSLocalizedDescriptionKey: "Spotify API request failed: \(body)"])
        }
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
            throw NSError(domain: "SpotifyService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing Spotify redirect URI."])
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

        return try await openWebAuthSession(
            url: components.url!,
            callbackScheme: callbackScheme()
        )
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

    private func fetchRecommendations(queryItems: [URLQueryItem]) async throws -> SpotifyRecommendationsResponse {
        var components = URLComponents()
        components.path = "/v1/recommendations"
        components.queryItems = queryItems

        let request = try await authorizedRequest(path: components.string ?? "/v1/recommendations")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(SpotifyRecommendationsResponse.self, from: data)
    }

    private func recommendationQueryItems(
        params: RunModeAudioParams,
        limit: Int,
        trackSeeds: [String],
        genreSeeds: [String],
        includeTempoBounds: Bool = true,
        includeMoodTargets: Bool = true
    ) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]

        if !trackSeeds.isEmpty {
            items.append(URLQueryItem(name: "seed_tracks", value: trackSeeds.joined(separator: ",")))
        }
        if !genreSeeds.isEmpty {
            items.append(URLQueryItem(name: "seed_genres", value: genreSeeds.joined(separator: ",")))
        }

        items.append(URLQueryItem(name: "target_tempo", value: String(Int(params.targetTempo.rounded()))))

        if includeTempoBounds {
            items.append(URLQueryItem(name: "min_tempo", value: String(Int(params.minTempo.rounded()))))
            items.append(URLQueryItem(name: "max_tempo", value: String(Int(params.maxTempo.rounded()))))
        }

        if includeMoodTargets {
            items.append(URLQueryItem(name: "target_energy", value: String(params.targetEnergy)))
            items.append(URLQueryItem(name: "target_valence", value: String(params.targetValence)))
        }

        return items
    }

    private static let scopes = [
        "user-read-private",
        "user-read-email",
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-top-read",
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

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
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

// MARK: - JoggingPhase

/// The current phase of the jogging workout flow.
enum JoggingPhase: Equatable {
    case idle
    case active
    case confirmingStop
    case finished
}

enum RunParticipantStatus: String {
    case running
    case invited
}

struct RunParticipant: Identifiable, Equatable {
    let id: String
    let displayName: String
    let username: String?
    var status: RunParticipantStatus

    var initials: String {
        let source = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "?" }
        let parts = source
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }
}

struct ActiveRunOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let participantCount: Int
}

struct UpcomingRunOption: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let participantCount: Int
    let status: String?
    let visibility: String
    let plannedStartAt: Date
}

enum RunLaunchMode: String, CaseIterable, Identifiable {
    case solo = "Solo"
    case crew = "Crew"

    var id: String { rawValue }
}

enum PlannedRunKind: String, CaseIterable, Identifiable {
    case solo = "Solo Event"
    case crew = "Crew Event"

    var id: String { rawValue }
}

enum RunAudioMode: String, CaseIterable, Identifiable {
    case recovery = "Recovery"
    case base = "Base"
    case tempo = "Tempo"
    case longRun = "Long Run"
    case race = "Race"

    var id: String { rawValue }
}

struct RunTrack: Equatable {
    let title: String
    let artist: String
    let vibe: String
}

struct RunCompletionSnapshot: Equatable {
    var distanceMeters: Double
    var durationSeconds: Int
    var avgPaceSecondsPerKm: Int?
    var caloriesBurned: Int
    var earnedMinutes: Int
    var countsAsRun: Bool
}

// MARK: - JoggingViewModel

/// View model for the jogging workout screen.
///
/// Wraps `JoggingTrackingManager` with UI-specific state management:
/// - Workout phases (idle, active, confirming stop, finished)
/// - Idle timer management
/// - Haptic feedback
/// - Formatted display values
@MainActor
final class JoggingViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var phase: JoggingPhase = .idle
    @Published private(set) var distanceMeters: Double = 0.0
    @Published private(set) var sessionDuration: TimeInterval = 0
    @Published private(set) var activeDuration: TimeInterval = 0
    @Published private(set) var pauseDuration: TimeInterval = 0
    @Published private(set) var currentPaceSecondsPerKm: Int?
    @Published private(set) var currentSpeed: Double = 0.0
    @Published private(set) var caloriesBurned: Int = 0
    @Published private(set) var routeLocations: [CLLocation] = []
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var activeDistanceMeters: Double = 0.0
    @Published private(set) var pauseDistanceMeters: Double = 0.0
    @Published private(set) var lastError: JoggingTrackingError?
    @Published private(set) var earnedMinutes: Int = 0
    @Published private(set) var completedRunSnapshot: RunCompletionSnapshot?
    @Published private(set) var dashboard: RunningDashboardData = .empty
    @Published private(set) var runParticipants: [RunParticipant] = []
    @Published private(set) var inviteableFriends: [RunParticipant] = []
    @Published private(set) var activeFriendRuns: [ActiveRunOption] = []
    @Published private(set) var upcomingRuns: [UpcomingRunOption] = []
    @Published private(set) var isLoadingRunSocialData: Bool = false
    @Published private(set) var selectedLiveRunSessionId: String?
    @Published private(set) var selectedUpcomingEventId: String?
    @Published var plannedRunKind: PlannedRunKind = .crew
    @Published var plannedRunTitle: String = "Crew Run"
    @Published var plannedRunDate: Date = JoggingViewModel.defaultPlannedRunDate()
    @Published private(set) var isCreatingPlannedRun: Bool = false
    @Published private(set) var plannedRunStatusMessage: String?
    @Published private(set) var isUpdatingUpcomingRun: Bool = false
    @Published private(set) var isInvitingToLiveRun: Bool = false
    @Published private(set) var isLeavingLiveRun: Bool = false
    @Published private(set) var isRejoiningLiveRun: Bool = false
    @Published private(set) var activeRunLeaderName: String?
    @Published private(set) var activeRunStateLabel: String?
    @Published private(set) var liveRunBannerMessage: String?
    @Published private(set) var lastDetachedLiveRunSessionId: String?
    @Published var launchMode: RunLaunchMode = .solo
    @Published var selectedAudioMode: RunAudioMode = .base
    @Published private(set) var spotifyConnected: Bool = false
    @Published private(set) var spotifyAppInstalled: Bool = false
    @Published private(set) var spotifyStatusDetail: String = "Spotify web fallback only"
    @Published private(set) var spotifyAccountName: String?
    @Published private(set) var spotifyProductTier: String?
    @Published private(set) var spotifyPlaybackLabel: String = "No playback detected"
    @Published private(set) var spotifyGeneratorStatusMessage: String?
    @Published private(set) var spotifyNowPlayingTitle: String?
    @Published private(set) var spotifyNowPlayingArtist: String?
    @Published private(set) var spotifyIsPlaying: Bool = false
    @Published private(set) var jamActive: Bool = false
    @Published private(set) var jamListenerCount: Int = 1
    @Published private(set) var jamHostDisplayName: String = "You"
    @Published private(set) var isCurrentUserInJam: Bool = false
    @Published private(set) var currentTrack: RunTrack = RunTrack(
        title: "Night Drive Tempo",
        artist: "PushUp Run Club",
        vibe: "160 BPM • Focus"
    )
    @Published private(set) var modeQueue: [SpotifyRecommendedRunTrack] = []
    @Published private(set) var modeQueueIndex: Int = 0
    @Published private(set) var isLoadingModeQueue: Bool = false

    // MARK: - Private

    let trackingManager: JoggingTrackingManager
    private let spotifyService: SpotifyService
    private var cancellables = Set<AnyCancellable>()
    private var joggingObservationJob: Kotlinx_coroutines_coreJob?
    private var liveRunObservationJob: Kotlinx_coroutines_coreJob?
    private var currentUserId: String?
    private var currentUserDisplayName: String = "You"
    private var currentUsername: String?
    private var presenceHeartbeat: AnyCancellable?
    private var socialRefreshTimer: AnyCancellable?
    private var activeSessionRefreshTimer: AnyCancellable?
    private var spotifyRefreshTimer: AnyCancellable?
    private var liveRunBannerResetTask: Task<Void, Never>?
    private var lastObservedLeaderUserId: String?

    // MARK: - Init

    /// Creates a view model with the given tracking manager.
    /// Must be called from the main actor since JoggingTrackingManager is @MainActor-isolated.
    init(
        trackingManager: JoggingTrackingManager,
        spotifyService: SpotifyService = .shared
    ) {
        self.trackingManager = trackingManager
        self.spotifyService = spotifyService
        applyTrackPresetForMode()
        refreshSpotifyState()
        observeTrackingManager()
        startSocialRefreshLoop()
        Task { await startDashboardObserving() }
        Task { await loadRunSocialData() }
        Task { await refreshSpotifyDetailsIfNeeded() }
    }

    /// Convenience initialiser that creates a default tracking manager.
    /// Must be called from the main actor.
    convenience init() {
        self.init(
            trackingManager: JoggingTrackingManager(),
            spotifyService: .shared
        )
    }

    // MARK: - Public API

    /// Starts the jogging workout.
    func startWorkout() {
        Task { await startWorkoutFlow() }
    }

    /// Requests confirmation before stopping.
    func requestStop() {
        phase = .confirmingStop
    }

    /// Cancels the stop request and resumes the workout.
    func cancelStop() {
        phase = .active
    }

    /// Confirms stopping the workout.
    func confirmStop() {
        completedRunSnapshot = RunCompletionSnapshot(
            distanceMeters: distanceMeters,
            durationSeconds: max(0, Int(activeDuration)),
            avgPaceSecondsPerKm: currentPaceSecondsPerKm,
            caloriesBurned: caloriesBurned,
            earnedMinutes: distanceMeters >= 100 ? max(1, Int(distanceMeters / 1000.0)) : 0,
            countsAsRun: distanceMeters > 0
        )
        if let sessionId = selectedLiveRunSessionId, let userId = currentUserId {
            DataBridge.shared.finishLiveRunSession(sessionId: sessionId, userId: userId) { _ in }
        }
        trackingManager.stopTracking()
        stopPresenceHeartbeat()
        stopActiveSessionRefreshLoop()
        stopSpotifyRefreshLoop()
        activeRunStateLabel = nil
        activeRunLeaderName = nil
        clearLiveRunBanner()
        selectedLiveRunSessionId = nil
        lastDetachedLiveRunSessionId = nil
        UIApplication.shared.isIdleTimerDisabled = false

        // Calculate earned minutes
        earnedMinutes = completedRunSnapshot?.earnedMinutes ?? 0

        phase = .finished
    }

    /// Requests location permission.
    func requestLocationPermission() {
        trackingManager.locationManager.requestAuthorization()
    }

    func pauseWorkout() {
        trackingManager.pauseTracking()
    }

    func resumeWorkout() {
        trackingManager.resumeTracking()
    }

    func loadRunSocialData() async {
        isLoadingRunSocialData = true

        if let currentUser = await AuthService.shared.getCurrentUser() {
            currentUserId = currentUser.id
            let safeDisplayName = currentUser.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            currentUserDisplayName = safeDisplayName.isEmpty ? "You" : safeDisplayName
            currentUsername = currentUser.username
            let me = RunParticipant(
                id: currentUser.id,
                displayName: currentUserDisplayName,
                username: currentUser.username,
                status: .running
            )
            if !runParticipants.contains(where: { $0.id == me.id }) {
                runParticipants = [me]
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            FriendsBridge.shared.getFriends(
                onResult: { [weak self] friends in
                    guard let self else { continuation.resume(); return }
                    let mapped = friends.map {
                        RunParticipant(
                            id: $0.id,
                            displayName: ($0.displayName?.isEmpty == false ? $0.displayName! : ($0.username ?? "Unknown")),
                            username: $0.username,
                            status: .invited
                        )
                    }
                    self.inviteableFriends = mapped
                    continuation.resume()
                },
                onError: { [weak self] _ in
                    self?.inviteableFriends = []
                    continuation.resume()
                }
            )
        }

        await refreshRunOptions()
        isLoadingRunSocialData = false
    }

    func inviteFriendToRun(_ friendId: String) {
        Task { await inviteFriendToRunFlow(friendId) }
    }

    private func inviteFriendToRunFlow(_ friendId: String) async {
        if let sessionId = selectedLiveRunSessionId {
            guard !isInvitingToLiveRun else { return }
            isInvitingToLiveRun = true
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DataBridge.shared.inviteUserToLiveRunSession(sessionId: sessionId, userId: friendId) { [weak self] success in
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    self.isInvitingToLiveRun = false
                    self.plannedRunStatusMessage = success.boolValue ? "Live run invite sent." : "Failed to invite runner."
                    Task {
                        await self.loadRunSocialData()
                    }
                    continuation.resume()
                }
            }
            return
        }

        guard let idx = inviteableFriends.firstIndex(where: { $0.id == friendId }) else { return }
        var invited = inviteableFriends.remove(at: idx)
        invited.status = .invited
        if !runParticipants.contains(where: { $0.id == invited.id }) {
            runParticipants.append(invited)
        }
        launchMode = .crew
        plannedRunStatusMessage = "Added \(invited.displayName) to your crew."
    }

    func removeInvitedParticipant(_ participantId: String) {
        guard selectedLiveRunSessionId == nil, selectedUpcomingEventId == nil else {
            plannedRunStatusMessage = "Revoke pending invites before joining or selecting a crew run."
            return
        }
        guard let index = runParticipants.firstIndex(where: { $0.id == participantId && $0.status == .invited }) else { return }

        let participant = runParticipants.remove(at: index)
        if !inviteableFriends.contains(where: { $0.id == participant.id }) {
            inviteableFriends.append(
                RunParticipant(
                    id: participant.id,
                    displayName: participant.displayName,
                    username: participant.username,
                    status: .invited
                )
            )
            inviteableFriends.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }

        if !runParticipants.contains(where: { $0.status == .invited }),
           selectedLiveRunSessionId == nil,
           selectedUpcomingEventId == nil {
            launchMode = .solo
        }
        plannedRunStatusMessage = "Invite for \(participant.displayName) revoked."
    }

    func createPlannedRun() {
        Task { await createPlannedRunFlow() }
    }

    func setPlannedRunKind(_ kind: PlannedRunKind) {
        plannedRunKind = kind

        let trimmedTitle = plannedRunTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty || trimmedTitle == "Crew Run" || trimmedTitle == "Solo Run" {
            plannedRunTitle = kind == .solo ? "Solo Run" : "Crew Run"
        }
    }

    func acceptUpcomingRun(_ eventId: String) {
        Task { await respondToUpcomingRun(eventId: eventId, accept: true) }
    }

    func declineUpcomingRun(_ eventId: String) {
        Task { await respondToUpcomingRun(eventId: eventId, accept: false) }
    }

    func checkInUpcomingRun(_ eventId: String) {
        Task { await checkInUpcomingRunFlow(eventId: eventId) }
    }

    func leaveCurrentLiveRun() {
        Task { await leaveCurrentLiveRunFlow() }
    }

    func rejoinLastLiveRun() {
        Task { await rejoinLastLiveRunFlow() }
    }

    func connectSpotify() {
        Task { await connectSpotifyFlow() }
    }

    func cycleAudioMode() {
        let allModes = RunAudioMode.allCases
        guard let currentIndex = allModes.firstIndex(of: selectedAudioMode) else { return }
        let nextIndex = allModes.index(after: currentIndex)
        selectedAudioMode = nextIndex < allModes.endIndex ? allModes[nextIndex] : allModes[allModes.startIndex]
        applyCurrentModePreset()
    }

    func applyCurrentModePreset() {
        guard spotifyConnected else {
            applyTrackPresetForMode()
            spotifyGeneratorStatusMessage = "Connect Spotify to generate a dynamic run queue."
            return
        }
        spotifyGeneratorStatusMessage = "Generating \(selectedAudioMode.rawValue) tracks..."
        Task { await loadModeRecommendations() }
    }

    func startJam() {
        let opened = spotifyService.openModePreset(selectedAudioMode)
        refreshSpotifyState()
        jamActive = true
        isCurrentUserInJam = true
        jamListenerCount = max(runParticipants.filter { $0.status == .running }.count, 1)
        jamHostDisplayName = currentUserDisplayName
        showLiveRunBanner(opened ? "Run Jam started on Spotify." : "Run Jam started. Spotify handoff failed.")
    }

    func joinJam() {
        let opened = spotifyService.openTrack(currentTrack)
        refreshSpotifyState()
        jamActive = true
        isCurrentUserInJam = true
        jamListenerCount = max(jamListenerCount, max(runParticipants.filter { $0.status == .running }.count, 1))
        showLiveRunBanner(opened ? "You joined the Run Jam." : "You joined the Run Jam without Spotify handoff.")
    }

    func leaveJam() {
        isCurrentUserInJam = false
        jamListenerCount = max(jamListenerCount - 1, 0)
        if jamListenerCount == 0 {
            jamActive = false
        }
        showLiveRunBanner("You left the Run Jam.")
    }

    func nextTrack() {
        guard spotifyConnected else {
            applyTrackPresetForMode(advance: true)
            _ = spotifyService.openTrack(currentTrack)
            return
        }
        Task {
            // If we have a mode queue, play the next track from it
            if !modeQueue.isEmpty {
                let nextIdx = modeQueueIndex + 1
                if nextIdx < modeQueue.count {
                    modeQueueIndex = nextIdx
                    await playModeQueueTrack(at: nextIdx)
                } else {
                    // Queue exhausted — fetch fresh recommendations
                    await loadModeRecommendations(andPlay: true)
                }
            } else {
                // No queue, just skip via API
                do {
                    try await spotifyService.skipToNext()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await refreshSpotifyDetailsIfNeeded(force: true)
                } catch { }
            }
        }
    }

    func previousTrack() {
        guard spotifyConnected else { return }
        Task {
            if !modeQueue.isEmpty, modeQueueIndex > 0 {
                modeQueueIndex -= 1
                await playModeQueueTrack(at: modeQueueIndex)
            } else {
                do {
                    try await spotifyService.skipToPrevious()
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await refreshSpotifyDetailsIfNeeded(force: true)
                } catch { }
            }
        }
    }

    func togglePlayback() {
        guard spotifyConnected else {
            connectSpotify()
            return
        }
        Task {
            do {
                if spotifyIsPlaying {
                    try await spotifyService.pausePlayback()
                    spotifyIsPlaying = false
                } else {
                    try await spotifyService.resumePlayback()
                    spotifyIsPlaying = true
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshSpotifyDetailsIfNeeded(force: true)
            } catch {
                _ = spotifyService.openConnectDestination()
            }
        }
    }

    /// Plays a specific track from the mode queue and queues the next few tracks.
    func playFromModeQueue(at index: Int) {
        guard spotifyConnected, index < modeQueue.count else { return }
        modeQueueIndex = index
        Task { await playModeQueueTrack(at: index) }
    }

    func selectActiveRun(_ sessionId: String) {
        selectedLiveRunSessionId = sessionId
        selectedUpcomingEventId = nil
        launchMode = .crew
    }

    func selectUpcomingRun(_ eventId: String) {
        selectedUpcomingEventId = eventId
        selectedLiveRunSessionId = nil
        if let run = upcomingRuns.first(where: { $0.id == eventId }) {
            launchMode = run.visibility.uppercased() == "PRIVATE" ? .solo : .crew
        } else {
            launchMode = .crew
        }
    }

    func setLaunchMode(_ mode: RunLaunchMode) {
        launchMode = mode
    }

    func startUpcomingRun(_ run: UpcomingRunOption) {
        selectUpcomingRun(run.id)
        launchMode = run.visibility.uppercased() == "PRIVATE" ? .solo : .crew
        startWorkout()
    }

    var startActionTitle: String {
        if launchMode == .solo {
            return hasLocationPermission ? "Start Solo Run" : "Enable Location"
        }
        if selectedLiveRunSessionId != nil {
            return "Join Run"
        }
        if selectedUpcomingEventId != nil {
            return "Start Planned Run"
        }
        if runParticipants.contains(where: { $0.status == .invited }) {
            return "Start Crew Run"
        }
        return hasLocationPermission ? "Start Run" : "Enable Location"
    }

    var socialSelectionSummary: String {
        if launchMode == .solo {
            let invitedCount = runParticipants.filter { $0.status == .invited }.count
            if invitedCount > 0 {
                return "Solo selected - \(invitedCount) pending invite\(invitedCount == 1 ? "" : "s") kept for later"
            }
            return "Solo run"
        }
        if let activeRun = activeFriendRuns.first(where: { $0.id == selectedLiveRunSessionId }) {
            return activeRun.subtitle
        }
        if let upcomingRun = upcomingRuns.first(where: { $0.id == selectedUpcomingEventId }) {
            return upcomingRun.visibility.uppercased() == "PRIVATE"
                ? "Planned solo event - \(Self.upcomingDayTimeFormatter.string(from: upcomingRun.plannedStartAt))"
                : upcomingRun.subtitle
        }
        let invitedCount = runParticipants.filter { $0.status == .invited }.count
        if invitedCount > 0 {
            return "\(invitedCount) invited - friends-visible live session"
        }
        return "Solo run"
    }

    var upcomingEventCountLabel: String {
        upcomingRuns.isEmpty ? "No events planned" : "\(upcomingRuns.count) future event\(upcomingRuns.count == 1 ? "" : "s")"
    }

    var selectedUpcomingRun: UpcomingRunOption? {
        guard let selectedUpcomingEventId else { return nil }
        return upcomingRuns.first(where: { $0.id == selectedUpcomingEventId })
    }

    var nextUpcomingRunSummary: String {
        guard let next = upcomingRuns.sorted(by: { $0.plannedStartAt < $1.plannedStartAt }).first else {
            return "Plan a run with friends and it will show up here."
        }
        return "\(Self.upcomingDayTimeFormatter.string(from: next.plannedStartAt)) - \(next.title)"
    }

    var calendarHighlightedDates: Set<Date> {
        Set(upcomingRuns.map { Calendar.current.startOfDay(for: $0.plannedStartAt) })
    }

    func upcomingRuns(on day: Date) -> [UpcomingRunOption] {
        let calendar = Calendar.current
        return upcomingRuns
            .filter { calendar.isDate($0.plannedStartAt, inSameDayAs: day) }
            .sorted { $0.plannedStartAt < $1.plannedStartAt }
    }

    var canCreatePlannedRun: Bool {
        currentUserId != nil &&
        !plannedRunTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var plannedRunKindSummary: String {
        switch plannedRunKind {
        case .solo:
            return "Creates a private planned run just for you."
        case .crew:
            return "Creates a crew event that friends can join or accept."
        }
    }

    var musicCardSubtitle: String {
        if !spotifyConnected {
            return "Open Spotify"
        }
        if jamActive {
            return isCurrentUserInJam ? "Jam live with \(jamListenerCount) runners" : "Jam active - join now"
        }
        return spotifyNowPlayingTitle ?? "No playback"
    }

    var jamStatusLabel: String {
        if jamActive {
            return isCurrentUserInJam
                ? "Jam live • \(jamListenerCount) listening"
                : "Jam active • hosted by \(jamHostDisplayName)"
        }
        if spotifyConnected, spotifyIsPlaying { return "Spotify live" }
        if spotifyConnected { return "Spotify connected" }
        return spotifyAppInstalled ? "Spotify app installed" : "Spotify web handoff"
    }

    func openSpotifyApp() {
        _ = spotifyService.openConnectDestination()
    }

    func handleSpotifySecondaryAction() {
        if spotifyConnected {
            spotifyService.disconnect()
            refreshSpotifyState()
            spotifyAccountName = nil
            spotifyProductTier = nil
            spotifyPlaybackLabel = "No playback detected"
            spotifyNowPlayingTitle = nil
            spotifyNowPlayingArtist = nil
            spotifyIsPlaying = false
            stopSpotifyRefreshLoop()
            plannedRunStatusMessage = "Spotify disconnected."
        } else {
            let opened = spotifyService.openConnectDestination()
            plannedRunStatusMessage = opened ? "Opened Spotify." : "Could not open Spotify."
        }
    }

    func upcomingRunPrimaryActionTitle(for run: UpcomingRunOption) -> String {
        switch run.status?.uppercased() {
        case "CHECKED_IN":
            return selectedUpcomingEventId == run.id ? "Selected" : "Ready"
        case "ACCEPTED":
            return selectedUpcomingEventId == run.id ? "Selected" : "Check In"
        case "INVITED":
            return "Accept"
        case "DECLINED":
            return "Rejoin"
        default:
            return selectedUpcomingEventId == run.id ? "Selected" : "Queue"
        }
    }

    func handleUpcomingRunPrimaryAction(_ run: UpcomingRunOption) {
        switch run.status?.uppercased() {
        case "CHECKED_IN":
            selectUpcomingRun(run.id)
        case "ACCEPTED":
            checkInUpcomingRun(run.id)
        case "INVITED", "DECLINED":
            acceptUpcomingRun(run.id)
        default:
            selectUpcomingRun(run.id)
        }
    }

    private func startWorkoutFlow() async {
        guard hasLocationPermission else {
            requestLocationPermission()
            return
        }

        completedRunSnapshot = nil
        earnedMinutes = 0

        let resolvedUserId: String?
        if let currentUserId {
            resolvedUserId = currentUserId
        } else {
            resolvedUserId = await AuthService.shared.getCurrentUser()?.id
        }
        guard let userId = resolvedUserId else {
            phase = .active
            UIApplication.shared.isIdleTimerDisabled = true
            trackingManager.startTracking()
            return
        }

        let linkedLiveSessionId: String?
        if launchMode == .crew {
            if let existingSessionId = selectedLiveRunSessionId {
                linkedLiveSessionId = await joinSelectedLiveRun(sessionId: existingSessionId, userId: userId)
            } else if let upcomingEventId = selectedUpcomingEventId {
                linkedLiveSessionId = await startLiveRun(userId: userId, linkedEventId: upcomingEventId)
            } else if runParticipants.contains(where: { $0.status == .invited }) {
                linkedLiveSessionId = await startLiveRun(userId: userId, linkedEventId: nil)
            } else {
                linkedLiveSessionId = nil
            }
        } else {
            linkedLiveSessionId = nil
        }

        phase = .active
        UIApplication.shared.isIdleTimerDisabled = true
        trackingManager.startTracking(liveRunSessionId: linkedLiveSessionId)
        startSpotifyRefreshLoop()

        if let linkedLiveSessionId {
            beginObservingLiveRun(sessionId: linkedLiveSessionId)
            startPresenceHeartbeat()
            startActiveSessionRefreshLoop(sessionId: linkedLiveSessionId)
        }
    }

    private func refreshSpotifyState() {
        spotifyConnected = spotifyService.hasValidSession()
        spotifyAppInstalled = spotifyService.isSpotifyAppInstalled()
        spotifyStatusDetail = spotifyService.sessionStatusDescription
    }

    private func connectSpotifyFlow() async {
        let result = await spotifyService.connect()
        refreshSpotifyState()
        switch result {
        case .connected:
            plannedRunStatusMessage = "Spotify connected for your next run."
            spotifyGeneratorStatusMessage = "Spotify connected. Generate a fresh run queue."
            await refreshSpotifyDetailsIfNeeded()
            if phase == .active {
                startSpotifyRefreshLoop()
            }
        case .openedExternal:
            plannedRunStatusMessage = spotifyAppInstalled
                ? "Opened Spotify. Add SpotifyClientID to enable in-app auth."
                : "Opened Spotify on the web. Add SpotifyClientID to enable in-app auth."
            spotifyGeneratorStatusMessage = plannedRunStatusMessage
        case .unavailable(let message):
            plannedRunStatusMessage = message
            spotifyGeneratorStatusMessage = message
        }
    }

    func refreshSpotifyDetails() {
        Task { await refreshSpotifyDetailsIfNeeded(force: true) }
    }

    private func refreshSpotifyDetailsIfNeeded(force: Bool = false) async {
        guard spotifyConnected else {
            if force {
                spotifyAccountName = nil
                spotifyProductTier = nil
                spotifyPlaybackLabel = "No playback detected"
                spotifyNowPlayingTitle = nil
                spotifyNowPlayingArtist = nil
                spotifyIsPlaying = false
            }
            return
        }

        if !force, phase != .active, spotifyAccountName != nil, spotifyPlaybackLabel != "No playback detected" {
            return
        }

        do {
            async let profile = spotifyService.fetchProfile()
            async let playback = spotifyService.fetchPlaybackState()
            let (resolvedProfile, resolvedPlayback) = try await (profile, playback)
            spotifyAccountName = resolvedProfile.displayName
            spotifyProductTier = resolvedProfile.product
            if let resolvedPlayback {
                spotifyNowPlayingTitle = resolvedPlayback.trackTitle
                spotifyNowPlayingArtist = resolvedPlayback.artistName
                spotifyIsPlaying = resolvedPlayback.isPlaying
                spotifyPlaybackLabel = resolvedPlayback.isPlaying
                    ? "\(resolvedPlayback.trackTitle) - \(resolvedPlayback.artistName)"
                    : "Paused: \(resolvedPlayback.trackTitle) - \(resolvedPlayback.artistName)"
                if let deviceName = resolvedPlayback.deviceName, !deviceName.isEmpty {
                    spotifyStatusDetail = "\(spotifyService.sessionStatusDescription) on \(deviceName)"
                } else {
                    spotifyStatusDetail = spotifyService.sessionStatusDescription
                }
            } else {
                spotifyNowPlayingTitle = nil
                spotifyNowPlayingArtist = nil
                spotifyIsPlaying = false
                spotifyPlaybackLabel = "No active playback"
                spotifyStatusDetail = spotifyService.sessionStatusDescription
            }
        } catch {
            spotifyNowPlayingTitle = nil
            spotifyNowPlayingArtist = nil
            spotifyIsPlaying = false
            spotifyStatusDetail = "Spotify connected, but details could not be loaded"
            spotifyPlaybackLabel = "Playback unavailable"
        }
    }

    private func refreshRunOptions() async {
        guard let userId = currentUserId else {
            activeFriendRuns = []
            upcomingRuns = []
            return
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.fetchFriendsActiveRuns(userId: userId) { [weak self] sessions in
                self?.activeFriendRuns = sessions.map {
                    ActiveRunOption(
                        id: $0.id,
                        title: "Live Run",
                        subtitle: "\($0.participantCount) runners - \($0.state.capitalized)",
                        participantCount: Int($0.participantCount)
                    )
                }
                continuation.resume()
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.fetchUpcomingRunEvents(userId: userId) { [weak self] events in
                self?.upcomingRuns = events.map {
                    UpcomingRunOption(
                        id: $0.id,
                        title: $0.title,
                        subtitle: Self.formatUpcomingSubtitle(
                            plannedStartAt: $0.plannedStartAt,
                            participantCount: Int($0.participantCount)
                        ),
                        participantCount: Int($0.participantCount),
                        status: $0.currentUserStatus,
                        visibility: $0.visibility,
                        plannedStartAt: ISO8601DateFormatter().date(from: $0.plannedStartAt) ?? Date()
                    )
                }
                continuation.resume()
            }
        }
    }

    private func createPlannedRunFlow() async {
        guard !isCreatingPlannedRun else { return }
        guard let userId = currentUserId else { return }
        let inviteIds = plannedRunKind == .crew
            ? runParticipants.filter { $0.status == .invited }.map(\.id)
            : []

        let trimmedTitle = plannedRunTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            plannedRunStatusMessage = "Add a title for the planned run."
            return
        }

        isCreatingPlannedRun = true
        plannedRunStatusMessage = nil
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.createRunEvent(
                organizerUserId: userId,
                title: trimmedTitle,
                mode: "BASE",
                visibility: plannedRunKind == .solo ? "PRIVATE" : (inviteIds.isEmpty ? "FRIENDS" : "INVITE_ONLY"),
                plannedStartAt: isoFormatter.string(from: plannedRunDate),
                invitedUserIds: inviteIds,
                description: nil,
                plannedEndAt: nil,
                locationName: nil
            ) { [weak self] event in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.isCreatingPlannedRun = false
                if let event {
                    self.selectedUpcomingEventId = event.id
                    self.selectedLiveRunSessionId = nil
                    self.launchMode = self.plannedRunKind == .solo ? .solo : .crew
                    self.plannedRunStatusMessage = self.plannedRunKind == .solo ? "Solo event created." : "Crew event created."
                    Task { await self.refreshRunOptions() }
                } else {
                    self.plannedRunStatusMessage = "Failed to create planned run."
                }
                continuation.resume()
            }
        }
    }

    private func respondToUpcomingRun(eventId: String, accept: Bool) async {
        guard let userId = currentUserId, !isUpdatingUpcomingRun else { return }
        isUpdatingUpcomingRun = true
        plannedRunStatusMessage = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.respondToRunEvent(
                eventId: eventId,
                userId: userId,
                status: accept ? "ACCEPTED" : "DECLINED"
            ) { [weak self] success in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.isUpdatingUpcomingRun = false
                self.plannedRunStatusMessage = success.boolValue
                    ? (accept ? "Joined planned run." : "Declined planned run.")
                    : "Failed to update planned run."
                Task { await self.refreshRunOptions() }
                continuation.resume()
            }
        }
    }

    private func checkInUpcomingRunFlow(eventId: String) async {
        guard let userId = currentUserId, !isUpdatingUpcomingRun else { return }
        isUpdatingUpcomingRun = true
        plannedRunStatusMessage = nil

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.checkInRunEvent(eventId: eventId, userId: userId) { [weak self] success in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.isUpdatingUpcomingRun = false
                self.plannedRunStatusMessage = success.boolValue ? "Checked in for planned run." : "Failed to check in."
                Task { await self.refreshRunOptions() }
                continuation.resume()
            }
        }
    }

    private func startLiveRun(userId: String, linkedEventId: String?) async -> String? {
        await withCheckedContinuation { continuation in
            DataBridge.shared.startLiveRunSession(
                leaderUserId: userId,
                mode: "BASE",
                visibility: "FRIENDS",
                linkedEventId: linkedEventId
            ) { [weak self] result in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let sessionId = result?.id
                if let sessionId {
                    self.selectedLiveRunSessionId = sessionId
                    self.selectedUpcomingEventId = nil
                }
                continuation.resume(returning: sessionId)
            }
        }
    }

    private func joinSelectedLiveRun(sessionId: String, userId: String) async -> String? {
        await withCheckedContinuation { continuation in
            DataBridge.shared.joinLiveRunSession(sessionId: sessionId, userId: userId) { success in
                continuation.resume(returning: success.boolValue ? sessionId : nil)
            }
        }
    }

    private func beginObservingLiveRun(sessionId: String) {
        liveRunObservationJob?.cancel(cause: nil)
        lastObservedLeaderUserId = nil
        liveRunObservationJob = DataBridge.shared.observeLiveRunSession(sessionId: sessionId) { [weak self] snapshot in
            self?.applyLiveRunSnapshot(snapshot)
        }
    }

    private func participantViewModel(userId: String, status: String) -> RunParticipant {
        let known = defaultRunParticipants().first(where: { $0.id == userId })
        let normalizedStatus = status.uppercased()
        return RunParticipant(
            id: userId,
            displayName: known?.displayName ?? displayName(for: userId),
            username: known?.username ?? (userId == currentUserId ? currentUsername : nil),
            status: normalizedStatus == "INVITED" ? .invited : .running
        )
    }

    private func defaultRunParticipants() -> [RunParticipant] {
        var base: [RunParticipant] = []
        if let userId = currentUserId {
            base.append(
                RunParticipant(
                    id: userId,
                    displayName: currentUserDisplayName,
                    username: currentUsername,
                    status: .running
                )
            )
        }
        base.append(contentsOf: runParticipants.filter { participant in
            base.contains(where: { $0.id == participant.id }) == false
        })
        return base
    }

    private func startPresenceHeartbeat() {
        stopPresenceHeartbeat()
        presenceHeartbeat = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pushPresenceHeartbeat()
            }
    }

    private func stopPresenceHeartbeat() {
        presenceHeartbeat?.cancel()
        presenceHeartbeat = nil
    }

    private func startActiveSessionRefreshLoop(sessionId: String) {
        activeSessionRefreshTimer?.cancel()
        activeSessionRefreshTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshActiveSessionSnapshot(sessionId: sessionId)
            }
    }

    private func stopActiveSessionRefreshLoop() {
        activeSessionRefreshTimer?.cancel()
        activeSessionRefreshTimer = nil
    }

    private func startSocialRefreshLoop() {
        socialRefreshTimer?.cancel()
        socialRefreshTimer = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshRunOptions() }
            }
    }

    private func startSpotifyRefreshLoop() {
        stopSpotifyRefreshLoop()
        guard spotifyConnected else { return }
        spotifyRefreshTimer = Timer.publish(every: 4, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.phase == .active else { return }
                Task { await self.refreshSpotifyDetailsIfNeeded(force: true) }
            }
    }

    private func stopSpotifyRefreshLoop() {
        spotifyRefreshTimer?.cancel()
        spotifyRefreshTimer = nil
    }

    private func pushPresenceHeartbeat() {
        guard phase == .active,
              let sessionId = selectedLiveRunSessionId,
              let userId = currentUserId else { return }
        let location = routeLocations.last
        let presenceState: String = isPaused ? "PAUSED" : "ACTIVE"
        let distance: Double = distanceMeters
        let duration: Int64 = Int64(activeDuration)
        let pace: KotlinInt? = currentPaceSecondsPerKm.map { KotlinInt(int: Int32($0)) }
        let latitude: KotlinDouble? = location != nil ? KotlinDouble(value: location!.coordinate.latitude) : nil
        let longitude: KotlinDouble? = location != nil ? KotlinDouble(value: location!.coordinate.longitude) : nil
        DataBridge.shared.updateLiveRunPresence(
            sessionId: sessionId,
            userId: userId,
            state: presenceState,
            distanceMeters: distance,
            durationSeconds: duration,
            paceSecondsPerKm: pace,
            latitude: latitude,
            longitude: longitude
        ) { _ in }
    }

    private func handleObservedLeaderChange(newLeaderUserId: String) {
        defer { lastObservedLeaderUserId = newLeaderUserId }
        guard let previousLeaderUserId = lastObservedLeaderUserId,
              previousLeaderUserId != newLeaderUserId else { return }

        let previousName = displayName(for: previousLeaderUserId)
        let newName = displayName(for: newLeaderUserId)
        showLiveRunBanner("\(previousName) finished. \(newName) leads now.")
    }

    private func displayName(for userId: String) -> String {
        if userId == currentUserId {
            return currentUserDisplayName
        }
        if let knownFriend = inviteableFriends.first(where: { $0.id == userId }) {
            return knownFriend.displayName
        }
        if let knownRunner = runParticipants.first(where: { $0.id == userId }) {
            return knownRunner.displayName
        }
        return "Runner"
    }

    private func labelForLiveState(_ raw: String) -> String? {
        switch raw.uppercased() {
        case "LIVE":
            return activeRunLeaderName.map { "Leader: \($0)" } ?? "Crew live"
        case "COOLDOWN":
            return "Cooldown"
        case "FINISHED":
            return "Finished"
        default:
            return nil
        }
    }

    private func applyTrackPresetForMode(advance: Bool = false) {
        let options: [RunAudioMode: [RunTrack]] = [
            .recovery: [
                RunTrack(title: "Soft Horizon", artist: "PushUp Run Club", vibe: "118 BPM • Recovery"),
                RunTrack(title: "Cool Down Signal", artist: "PushUp Run Club", vibe: "112 BPM • Easy")
            ],
            .base: [
                RunTrack(title: "Night Drive Tempo", artist: "PushUp Run Club", vibe: "160 BPM • Focus"),
                RunTrack(title: "City Grid Stride", artist: "PushUp Run Club", vibe: "158 BPM • Base")
            ],
            .tempo: [
                RunTrack(title: "Redline District", artist: "PushUp Run Club", vibe: "174 BPM • Tempo"),
                RunTrack(title: "Split Hunter", artist: "PushUp Run Club", vibe: "176 BPM • Fast")
            ],
            .longRun: [
                RunTrack(title: "Endless Blocks", artist: "PushUp Run Club", vibe: "148 BPM • Durable"),
                RunTrack(title: "Sunday Engine", artist: "PushUp Run Club", vibe: "150 BPM • Cruise")
            ],
            .race: [
                RunTrack(title: "Start Gun", artist: "PushUp Run Club", vibe: "182 BPM • Race"),
                RunTrack(title: "Final Kick", artist: "PushUp Run Club", vibe: "186 BPM • Push")
            ]
        ]

        let tracks = options[selectedAudioMode] ?? []
        guard !tracks.isEmpty else { return }
        if advance, let currentIndex = tracks.firstIndex(of: currentTrack) {
            let nextIndex = tracks.index(after: currentIndex)
            currentTrack = nextIndex < tracks.endIndex ? tracks[nextIndex] : tracks[tracks.startIndex]
        } else {
            currentTrack = tracks[tracks.startIndex]
        }
    }

    // MARK: - Mode Recommendations

    private func loadModeRecommendations(andPlay: Bool = true) async {
        isLoadingModeQueue = true
        modeQueue = []
        modeQueueIndex = 0
        let params = RunModeAudioParams.params(for: selectedAudioMode)
        defer { isLoadingModeQueue = false }

        do {
            let tracks = try await spotifyService.fetchRecommendations(params: params)
            guard !tracks.isEmpty else {
                throw NSError(
                    domain: "SpotifyService",
                    code: 27,
                    userInfo: [NSLocalizedDescriptionKey: "Spotify returned no tracks for \(selectedAudioMode.rawValue)."]
                )
            }
            modeQueue = tracks
            modeQueueIndex = 0
            plannedRunStatusMessage = "Loaded \(tracks.count) Spotify tracks for \(selectedAudioMode.rawValue)."
            spotifyGeneratorStatusMessage = "Loaded \(tracks.count) tracks for \(selectedAudioMode.rawValue)."

            // Update the currentTrack display from the first recommendation
            if let first = tracks.first {
                let bpmLabel = "\(Int(params.targetTempo)) BPM • \(selectedAudioMode.rawValue)"
                currentTrack = RunTrack(title: first.title, artist: first.artist, vibe: bpmLabel)

                if andPlay {
                    await playModeQueueTrack(at: 0)
                }
            }
        } catch {
            // Fallback to hardcoded presets if API fails
            modeQueue = []
            modeQueueIndex = 0
            applyTrackPresetForMode()
            plannedRunStatusMessage = "Spotify generator failed: \(error.localizedDescription)"
            spotifyGeneratorStatusMessage = "Spotify generator failed: \(error.localizedDescription)"
        }
    }

    private func playModeQueueTrack(at index: Int) async {
        guard index < modeQueue.count else { return }
        let track = modeQueue[index]
        let params = RunModeAudioParams.params(for: selectedAudioMode)
        let bpmLabel = "\(Int(params.targetTempo)) BPM • \(selectedAudioMode.rawValue)"
        currentTrack = RunTrack(title: track.title, artist: track.artist, vibe: bpmLabel)

        do {
            try await spotifyService.playTrack(uri: track.uri)
            spotifyGeneratorStatusMessage = "Playing \(track.title) on Spotify."

            // Pre-queue the next 2 tracks for gapless playback
            for offset in 1...2 {
                let queueIdx = index + offset
                guard queueIdx < modeQueue.count else { break }
                try? await spotifyService.addToQueue(uri: modeQueue[queueIdx].uri)
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            await refreshSpotifyDetailsIfNeeded(force: true)
        } catch {
            // Fallback: open in Spotify
            let fallbackTrack = RunTrack(title: track.title, artist: track.artist, vibe: bpmLabel)
            let opened = spotifyService.openTrack(fallbackTrack)
            plannedRunStatusMessage = opened
                ? "Playback handoff sent to Spotify for \(track.title)."
                : "Could not start playback. Open Spotify on an active device and try again."
            spotifyGeneratorStatusMessage = plannedRunStatusMessage
        }
    }

    private func showLiveRunBanner(_ message: String) {
        liveRunBannerResetTask?.cancel()
        liveRunBannerMessage = message
        liveRunBannerResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.liveRunBannerMessage = nil
            }
        }
    }

    private func clearLiveRunBanner() {
        liveRunBannerResetTask?.cancel()
        liveRunBannerResetTask = nil
        liveRunBannerMessage = nil
    }

    private func refreshActiveSessionSnapshot(sessionId: String) {
        DataBridge.shared.fetchLiveRunSessionSnapshot(sessionId: sessionId) { [weak self] snapshot in
            guard let self, let snapshot else { return }
            self.applyLiveRunSnapshot(snapshot)
        }
    }

    private func applyLiveRunSnapshot(_ snapshot: LiveRunSessionSnapshotResult) {
        let mapped = snapshot.participants.map { participant in
            participantViewModel(
                userId: participant.userId,
                status: participant.status
            )
        }
        runParticipants = mapped.isEmpty ? defaultRunParticipants() : mapped
        if let session = snapshot.session {
            handleObservedLeaderChange(newLeaderUserId: session.leaderUserId)
            activeRunLeaderName = displayName(for: session.leaderUserId)
            activeRunStateLabel = labelForLiveState(session.state)
            if session.state.uppercased() == "COOLDOWN" {
                showLiveRunBanner("Run is in cooldown. Jump back in before it closes.")
            } else if session.state.uppercased() == "FINISHED" {
                showLiveRunBanner("Group run finished.")
                stopActiveSessionRefreshLoop()
            }
        } else {
            activeRunLeaderName = nil
            activeRunStateLabel = nil
        }
    }

    private func leaveCurrentLiveRunFlow() async {
        guard let sessionId = selectedLiveRunSessionId,
              let userId = currentUserId,
              !isLeavingLiveRun else { return }
        isLeavingLiveRun = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DataBridge.shared.leaveLiveRunSession(sessionId: sessionId, userId: userId) { [weak self] success in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.isLeavingLiveRun = false
                if success.boolValue {
                    self.stopPresenceHeartbeat()
                    self.stopActiveSessionRefreshLoop()
                    self.liveRunObservationJob?.cancel(cause: nil)
                    self.selectedLiveRunSessionId = nil
                    self.lastDetachedLiveRunSessionId = sessionId
                    self.launchMode = .solo
                    self.activeRunLeaderName = nil
                    self.activeRunStateLabel = "Solo run"
                    self.runParticipants = self.defaultRunParticipants()
                    self.showLiveRunBanner("You left the crew run and continued solo.")
                } else {
                    self.showLiveRunBanner("Failed to leave crew run.")
                }
                continuation.resume()
            }
        }
    }

    private func rejoinLastLiveRunFlow() async {
        guard let sessionId = lastDetachedLiveRunSessionId,
              let userId = currentUserId,
              !isRejoiningLiveRun,
              phase == .active else { return }
        isRejoiningLiveRun = true

        let joinedSessionId = await joinSelectedLiveRun(sessionId: sessionId, userId: userId)
        isRejoiningLiveRun = false

        guard let joinedSessionId else {
            showLiveRunBanner("Rejoin failed. The crew run may have already ended.")
            return
        }

        selectedLiveRunSessionId = joinedSessionId
        lastDetachedLiveRunSessionId = nil
        launchMode = .crew
        beginObservingLiveRun(sessionId: joinedSessionId)
        startPresenceHeartbeat()
        startActiveSessionRefreshLoop(sessionId: joinedSessionId)
        pushPresenceHeartbeat()
        showLiveRunBanner("You rejoined the crew run.")
    }

    // MARK: - Formatted Values

    /// Distance formatted as "X.XX km" or "XXX m".
    var formattedDistance: String {
        let distanceValue = phase == .finished ? (completedRunSnapshot?.distanceMeters ?? distanceMeters) : distanceMeters
        if distanceValue >= 1000 {
            return String(format: "%.2f km", distanceValue / 1000.0)
        } else {
            return String(format: "%.0f m", distanceValue)
        }
    }

    /// Duration formatted as "MM:SS" or "H:MM:SS".
    var formattedDuration: String {
        let totalSeconds = max(0, phase == .finished ? (completedRunSnapshot?.durationSeconds ?? Int(activeDuration)) : Int(activeDuration))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    /// Pace formatted as "M:SS /km" or "--:--".
    var formattedPace: String {
        let paceValue = phase == .finished ? (completedRunSnapshot?.avgPaceSecondsPerKm ?? currentPaceSecondsPerKm) : currentPaceSecondsPerKm
        guard let pace = paceValue, pace > 0 else {
            return "--:-- /km"
        }
        let minutes = pace / 60
        let seconds = pace % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    /// Speed formatted as "X.X km/h".
    var formattedSpeed: String {
        let kmh = currentSpeed * 3.6
        return String(format: "%.1f km/h", kmh)
    }

    var stopConfirmationTitle: String {
        distanceMeters > 0 ? "End Run?" : "End Run Without Saving?"
    }

    var stopConfirmationMessage: String {
        if distanceMeters > 0 {
            return "Are you sure you want to end your run?"
        }
        return "This session has 0 m distance and will not count as a run or be saved to your history."
    }

    var completedRunCounts: Bool {
        completedRunSnapshot?.countsAsRun ?? true
    }

    var finishedTitle: String {
        completedRunCounts ? "Run Complete" : "Run Not Counted"
    }

    var finishedSubtitle: String {
        completedRunCounts
            ? "This run was saved to your history and counted toward your activity."
            : "No distance was tracked, so this session was discarded and not saved as a run."
    }

    var finishedCaloriesBurned: Int {
        phase == .finished ? (completedRunSnapshot?.caloriesBurned ?? caloriesBurned) : caloriesBurned
    }

    /// Whether the user has location permission.
    var hasLocationPermission: Bool {
        trackingManager.locationManager.hasLocationPermission
    }

    // MARK: - Private

    private func startDashboardObserving() async {
        guard joggingObservationJob == nil else { return }
        guard let user = await AuthService.shared.getCurrentUser() else {
            dashboard = .empty
            return
        }

        joggingObservationJob = DataBridge.shared.observeJoggingSessions(userId: user.id) { [weak self] sessions in
            guard let self else { return }
            let completed = sessions.filter { $0.endedAt != nil && $0.distanceMeters > 0 }
            self.dashboard = RunningDashboardData.build(from: completed)
        }
    }

    private func observeTrackingManager() {
        trackingManager.$distanceMeters
            .receive(on: DispatchQueue.main)
            .assign(to: &$distanceMeters)

        trackingManager.$sessionDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$sessionDuration)
        trackingManager.$activeDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeDuration)
        trackingManager.$pauseDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$pauseDuration)

        trackingManager.$currentPaceSecondsPerKm
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentPaceSecondsPerKm)

        trackingManager.$currentSpeed
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentSpeed)

        trackingManager.$caloriesBurned
            .receive(on: DispatchQueue.main)
            .assign(to: &$caloriesBurned)

        trackingManager.$routeLocations
            .receive(on: DispatchQueue.main)
            .assign(to: &$routeLocations)
        trackingManager.$isPaused
            .receive(on: DispatchQueue.main)
            .assign(to: &$isPaused)
        trackingManager.$activeDistanceMeters
            .receive(on: DispatchQueue.main)
            .assign(to: &$activeDistanceMeters)
        trackingManager.$pauseDistanceMeters
            .receive(on: DispatchQueue.main)
            .assign(to: &$pauseDistanceMeters)

        trackingManager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastError)

        trackingManager.$lastFinishedSummary
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] summary in
                guard let self else { return }
                let paceValue = summary.session.avgPaceSecondsPerKm?.intValue
                let snapshot = RunCompletionSnapshot(
                    distanceMeters: summary.session.distanceMeters,
                    durationSeconds: Int(summary.session.durationSeconds),
                    avgPaceSecondsPerKm: paceValue,
                    caloriesBurned: Int(summary.session.caloriesBurned),
                    earnedMinutes: Int(summary.earnedCredits / 60),
                    countsAsRun: summary.countsAsRun
                )
                self.completedRunSnapshot = snapshot
                self.earnedMinutes = snapshot.earnedMinutes
            }
            .store(in: &cancellables)
    }

    private static func formatUpcomingSubtitle(plannedStartAt: String, participantCount: Int) -> String {
        let fallback = "\(participantCount) runners planned"
        guard let date = ISO8601DateFormatter().date(from: plannedStartAt) else { return fallback }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d • HH:mm"
        return "\(formatter.string(from: date)) - \(participantCount) runners"
    }

    private static let upcomingDayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d • HH:mm"
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    private static func defaultPlannedRunDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(
            bySettingHour: 7,
            minute: 0,
            second: 0,
            of: tomorrow
        ) ?? tomorrow
    }

    deinit {
        joggingObservationJob?.cancel(cause: nil)
        liveRunObservationJob?.cancel(cause: nil)
        presenceHeartbeat?.cancel()
        socialRefreshTimer?.cancel()
        activeSessionRefreshTimer?.cancel()
        liveRunBannerResetTask?.cancel()
    }
}

// MARK: - RunningDashboardData

struct RunningDashboardData {
    let weekDistanceMeters: Double
    let weekRuns: Int
    let weekEarnedMinutes: Int
    let averagePaceSecondsPerKm: Int?
    let bestDistanceMeters: Double
    let longestRunDurationSeconds: Int
    let recentRuns: [RecentRun]

    static let empty = RunningDashboardData(
        weekDistanceMeters: 0,
        weekRuns: 0,
        weekEarnedMinutes: 0,
        averagePaceSecondsPerKm: nil,
        bestDistanceMeters: 0,
        longestRunDurationSeconds: 0,
        recentRuns: []
    )

    struct RecentRun: Identifiable {
        let id: String
        let date: Date
        let distanceMeters: Double
        let durationSeconds: Int
        let earnedMinutes: Int
        let avgPaceSecondsPerKm: Int?
    }

    static func build(from sessions: [Shared.JoggingSession]) -> RunningDashboardData {
        let validSessions = sessions.filter { $0.endedAt != nil && $0.distanceMeters > 0 }
        guard !validSessions.isEmpty else { return .empty }

        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        let weekStart = calendar.date(
            byAdding: .day,
            value: -mondayOffset,
            to: calendar.startOfDay(for: today)
        ) ?? today

        let weekSessions = validSessions.filter { session in
            let date = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
            return date >= weekStart
        }

        let weekDistance = weekSessions.reduce(0.0) { $0 + $1.distanceMeters }
        let weekEarned = weekSessions.reduce(0) { $0 + Int($1.earnedTimeCreditSeconds / 60) }
        let paceValues = weekSessions.compactMap { $0.avgPaceSecondsPerKm?.intValue }.filter { $0 > 0 }
        let avgPace = paceValues.isEmpty ? nil : (paceValues.reduce(0, +) / paceValues.count)
        let bestDistance = validSessions.map(\.distanceMeters).max() ?? 0
        let longestDuration = validSessions.map { Int($0.durationSeconds) }.max() ?? 0

        let recent = validSessions
            .sorted(by: { $0.startedAt.epochSeconds > $1.startedAt.epochSeconds })
            .prefix(5)
            .map { session in
                let runDate = Date(timeIntervalSince1970: Double(session.startedAt.epochSeconds))
                return RecentRun(
                    id: session.id,
                    date: runDate,
                    distanceMeters: session.distanceMeters,
                    durationSeconds: Int(session.durationSeconds),
                    earnedMinutes: Int(session.earnedTimeCreditSeconds / 60),
                    avgPaceSecondsPerKm: session.avgPaceSecondsPerKm?.intValue
                )
            }

        return RunningDashboardData(
            weekDistanceMeters: weekDistance,
            weekRuns: weekSessions.count,
            weekEarnedMinutes: weekEarned,
            averagePaceSecondsPerKm: avgPace,
            bestDistanceMeters: bestDistance,
            longestRunDurationSeconds: longestDuration,
            recentRuns: Array(recent)
        )
    }

}
