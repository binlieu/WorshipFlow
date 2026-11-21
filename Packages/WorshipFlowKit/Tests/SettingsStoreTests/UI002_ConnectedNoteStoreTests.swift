// UI-002 Part 2: the typed "connected to" notes survive storage, with no schema change (they live in the profile's extra JSON).
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct UI002_ConnectedNoteStoreTests {
    @Test func notesOnAWindowProfileAndOnAMirrorRoundTrip() async throws {
        let store = try LibraryStore.inMemory()
        var a = ScreenProfile(name: "Sanctuary", role: .audience, destination: .display(2), mirrors: [.window])
        a.setConnectedNote("Projector", mirror: nil)
        a.setConnectedNote("Foyer TV", mirror: 0)
        let b = ScreenProfile(name: "Lobby", role: .audience, destination: .window)
        try await store.saveScreenProfiles([a, b])
        let back = try await store.screenProfiles()
        #expect(back == [a, b])
        #expect(back[0].connectedNote(mirror: 0) == "Foyer TV" && back[1].connectedTo.isEmpty)
    }
}
