// UI-002 Part 2: the optional free-text "connected to" note of each destination, stored with the screen profile.
import Testing
import Foundation
@testable import Domain

@Suite struct UI002_ConnectedNoteTests {
    private func profile() -> ScreenProfile {
        ScreenProfile(name: "Livestream", role: .broadcast,
                      destination: .sdi(deviceID: "d", connector: 1, keying: true, fillAlphaMode: .premultiplied), mirrors: [.window])
    }

    @Test func aNewProfileHasNoNotes() {
        let p = profile()
        #expect(p.connectedNote(mirror: nil) == nil && p.connectedNote(mirror: 0) == nil)
    }

    @Test func aNoteIsSetPerDestinationAndTrimmed() {
        var p = profile()
        p.setConnectedNote("  ATEM input 5  ", mirror: nil)
        p.setConnectedNote("Stage monitor", mirror: 0)
        #expect(p.connectedNote(mirror: nil) == "ATEM input 5")
        #expect(p.connectedNote(mirror: 0) == "Stage monitor")
    }

    @Test func anEmptyNoteMeansNothing() {
        var p = profile()
        p.setConnectedNote("x", mirror: nil)
        p.setConnectedNote("   ", mirror: nil)
        #expect(p.connectedNote(mirror: nil) == nil)
    }

    @Test func aNoteForAMirrorThatDoesNotExistIsIgnored() {
        var p = profile()
        p.setConnectedNote("ghost", mirror: 5)
        #expect(p.connectedNote(mirror: 5) == nil && p.connectedTo.isEmpty)
    }

    @Test func notesSurviveEncodingAndAProfileStoredBeforeNotesStillDecodes() throws {
        var p = profile()
        p.setConnectedNote("ATEM input 5", mirror: nil)
        let back = try JSONDecoder().decode(ScreenProfile.self, from: JSONEncoder().encode(p))
        #expect(back == p && back.connectedNote(mirror: nil) == "ATEM input 5")
        let old = """
        {"id":"\(UUID().uuidString)","name":"Old","role":"audience","destination":{"window":{}},"isEnabled":true}
        """
        let decoded = try JSONDecoder().decode(ScreenProfile.self, from: Data(old.utf8))
        #expect(decoded.connectedTo.isEmpty && decoded.connectedNote(mirror: nil) == nil)
    }
}
