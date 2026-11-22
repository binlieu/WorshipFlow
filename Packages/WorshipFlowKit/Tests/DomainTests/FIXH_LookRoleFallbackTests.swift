// FIX-H item 12 (UI-005b): the seeded Looks keep one entry per screen that existed when they were made. A screen added later has no
// entry of its own, so it takes the Look's entry for its role (the first screen of that role that has one). A screen that has its
// own entry keeps it, and a role the Look does not mention shows everything, as before.
import Testing
import Foundation
@testable import Domain

@Suite struct FIXH_LookRoleFallbackTests {
    let audience = ScreenProfile(name: "Sanctuary", role: .audience, destination: .window)
    let stage = ScreenProfile(name: "Stage", role: .stage, destination: .window)
    let broadcast = ScreenProfile(name: "Feed", role: .broadcast, destination: .window)

    var notes: Look { DesignLooks.make(profiles: [audience, stage, broadcast])[1] }

    @Test func aScreenAddedLaterTakesTheLooksEntryForItsRole() {
        let lobby = ScreenProfile(name: "Lobby", role: .audience, destination: .window)
        let second = ScreenProfile(name: "Overflow feed", role: .broadcast, destination: .window)
        let profiles = [audience, stage, broadcast, lobby, second]
        #expect(notes.screenLook(for: lobby.id, in: profiles).visibleLayers == [.background, .slide])
        #expect(notes.screenLook(for: second.id, in: profiles).visibleLayers == [.slide])
        // The old behaviour (no profiles to look at) still shows everything for an unknown screen.
        #expect(notes.screenLook(for: lobby.id) == .standard)
    }

    @Test func aScreenWithItsOwnEntryKeepsItAndAnUnmentionedRoleShowsEverything() {
        var look = notes
        let lobby = ScreenProfile(name: "Lobby", role: .audience, destination: .window)
        look.screens[lobby.id] = ScreenLook(themeID: nil, visibleLayers: [.slide, .props])
        let profiles = [audience, stage, broadcast, lobby]
        #expect(look.screenLook(for: lobby.id, in: profiles).visibleLayers == [.slide, .props])
        #expect(look.screenLook(for: audience.id, in: profiles).visibleLayers == [.background, .slide])
        let hall = ScreenProfile(name: "Stage 2", role: .stage, destination: .window)
        #expect(look.screenLook(for: hall.id, in: profiles + [hall]) == .standard)       // the Look has no stage entry
    }
}
