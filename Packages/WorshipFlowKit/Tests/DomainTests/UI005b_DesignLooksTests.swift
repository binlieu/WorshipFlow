// UI-005b item 6: the four Looks the design shows (Full, Notes, Lower 3rd, BG only). What each shows on each role, and that none can
// route speaker notes to an audience or broadcast screen (a Look has no notes layer; notes are the stage layout's).
import Testing
import Foundation
@testable import Domain

@Suite struct UI005b_DesignLooksTests {
    let audience = ScreenProfile(name: "Audience", role: .audience, destination: .window)
    let stage = ScreenProfile(name: "Stage", role: .stage, destination: .window)
    let broadcast = ScreenProfile(name: "Broadcast", role: .broadcast, destination: .window)
    var profiles: [ScreenProfile] { [audience, stage, broadcast] }

    func look(_ name: String) throws -> Look { try #require(DesignLooks.make(profiles: profiles).first { $0.name == name }) }
    func layers(_ look: Look, _ profile: ScreenProfile) -> Set<LayerKind> { look.screenLook(for: profile.id).visibleLayers }

    @Test func theFourLooksAreNamedAsTheDesignNamesThem() {
        let looks = DesignLooks.make(profiles: profiles)
        #expect(looks.map(\.name) == ["Full", "Notes", "Lower 3rd", "BG only"])
        #expect(Set(looks.map(\.id)).count == 4)
        #expect(DesignLooks.make(profiles: profiles).map(\.id) != looks.map(\.id))      // fresh ids each time: nothing is shared between libraries
    }

    @Test func fullShowsEverythingEverywhere() throws {
        let full = try look("Full")
        for p in profiles { #expect(layers(full, p) == [.background, .slide, .props]) }
    }

    @Test func notesKeepsTheRoomCleanAndLeavesNotesToTheStage() throws {
        let notes = try look("Notes")
        #expect(layers(notes, audience) == [.background, .slide])         // the words and the background, no props
        #expect(layers(notes, broadcast) == [.slide])                      // the words only
        #expect(layers(notes, stage) == [.background, .slide, .props])    // unchanged: the stage layout alone decides what it draws, notes included
    }

    @Test func lowerThirdDropsTheBackgroundOnTheBroadcastFeedOnly() throws {
        let lt = try look("Lower 3rd")
        #expect(layers(lt, broadcast) == [.slide, .props])
        #expect(layers(lt, audience) == [.background, .slide, .props])
    }

    @Test func bgOnlyShowsTheBackgroundAlone() throws {
        let bg = try look("BG only")
        #expect(layers(bg, audience) == [.background] && layers(bg, broadcast) == [.background])
    }

    @Test func aLookHasNoLayerThatCouldCarrySpeakerNotes() {
        #expect(Set(LayerKind.allCases) == [.background, .slide, .props])
    }

    @Test func noLookLeaksAnythingElseToAScreenItDoesNotName() throws {
        // A screen added later (not in `profiles`) is shown everything, like any Look: it is the default, not a design choice.
        let extra = ScreenProfile(name: "Hall", role: .audience, destination: .window)
        for l in DesignLooks.make(profiles: profiles) { #expect(l.screenLook(for: extra.id) == .standard) }
    }
}
