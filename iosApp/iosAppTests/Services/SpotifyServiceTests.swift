import Foundation
import Testing

@testable import iosApp

@Suite("SpotifyService")
struct SpotifyServiceTests {

    @Test("Connect destination uses app URL when Spotify is installed")
    func connectDestinationUsesApp() {
        let destination = SpotifyService.connectDestination(isSpotifyInstalled: true)
        #expect(destination == .app(URL(string: "spotify://")!))
    }

    @Test("Connect destination uses web URL when Spotify is not installed")
    func connectDestinationUsesWeb() {
        let destination = SpotifyService.connectDestination(isSpotifyInstalled: false)
        #expect(destination == .web(URL(string: "https://open.spotify.com/")!))
    }

    @Test("Mode destination includes playlist query")
    func modeDestinationIncludesQuery() {
        let destination = SpotifyService.modeDestination(mode: .tempo, isSpotifyInstalled: false)
        switch destination {
        case .web(let url):
            #expect(url.absoluteString.contains("tempo"))
            #expect(url.absoluteString.contains("playlist"))
        case .app:
            Issue.record("Expected web fallback URL")
        }
    }

    @Test("Track destination includes title and artist")
    func trackDestinationIncludesMetadata() {
        let track = RunTrack(
            title: "Night Drive Tempo",
            artist: "PushUp Run Club",
            vibe: "160 BPM"
        )
        let destination = SpotifyService.trackDestination(track: track, isSpotifyInstalled: true)
        switch destination {
        case .app(let url):
            #expect(url.absoluteString.contains("Night%20Drive%20Tempo"))
            #expect(url.absoluteString.contains("PushUp%20Run%20Club"))
        case .web:
            Issue.record("Expected app URL")
        }
    }
}
