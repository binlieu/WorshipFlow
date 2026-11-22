// FIX-H item 12 (UI-005b): the role fallback of a Look reaches what a screen added later actually draws.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct FIXH_LookRoleScenesTests {
    let audience = ScreenProfile(name: "Sanctuary", role: .audience, destination: .window)
    let stage = ScreenProfile(name: "Stage", role: .stage, destination: .window)
    let broadcast = ScreenProfile(name: "Feed", role: .broadcast, destination: .window)

    var notes: Look { DesignLooks.make(profiles: [audience, stage, broadcast])[1] }

    @Test func theFallbackReachesThePublishedScene() {
        let lobby = ScreenProfile(name: "Lobby", role: .audience, destination: .window)
        let profiles = [audience, stage, broadcast, lobby]
        let prop = Prop(name: "Logo", imagePath: "/x.png", frame: .full)
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Amazing grace")])))
        state.apply(.trigger(index: 0))
        let scenes = PublishedScenes(state: state, clockText: nil, profiles: profiles, look: notes, props: [prop])
        // Notes shows no props on an audience screen: the screen added later follows the screen that was there.
        #expect(scenes.scene(forScreen: lobby.id).overlayImages.count == scenes.scene(forScreen: audience.id).overlayImages.count)
        #expect(scenes.scene(forScreen: lobby.id).overlayImages.isEmpty)
    }
}
