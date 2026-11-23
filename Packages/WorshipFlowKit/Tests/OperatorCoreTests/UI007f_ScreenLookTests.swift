// UI-007f (OUT, SC-51): a screen can follow a Look of its own. A screen with its own Look composes with it, one without follows the show's Look,
// changing the show's Look never moves a screen that has its own, a deleted Look falls back, and nothing here changes what a library that uses no
// per-screen Look shows (UI007f_ScenesDigestTests). Choosing one is an explicit operator action that takes effect exactly as selecting the show's
// Look does (`onAppearanceChange`, nothing sooner or later).
import Testing
import Foundation
import CryptoKit
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI007f_ScreenLookTests {
    static let audience = UUID(uuidString: "00000000-0000-0000-0000-0000000A0001")!
    static let lobby = UUID(uuidString: "00000000-0000-0000-0000-0000000A0002")!
    static let stage = UUID(uuidString: "00000000-0000-0000-0000-0000000A0003")!

    static func profiles(lobbyLook: UUID? = nil) -> [ScreenProfile] {
        [ScreenProfile(id: audience, name: "Sanctuary", role: .audience, destination: .window),
         ScreenProfile(id: lobby, name: "Lobby", role: .audience, destination: .window, screenLookID: lobbyLook),
         ScreenProfile(id: stage, name: "Stage", role: .stage, destination: .window)]
    }

    static let sermon = Look(id: UUID(uuidString: "00000000-0000-0000-0000-0000000B0001")!, name: "Sermon", screens: [
        audience: ScreenLook(themeID: Theme.lowerThirdID, visibleLayers: [.slide]),
        lobby: ScreenLook(themeID: Theme.lowerThirdID, visibleLayers: [.slide])])
    static let worship = Look(id: UUID(uuidString: "00000000-0000-0000-0000-0000000B0002")!, name: "Worship", screens: [
        audience: ScreenLook(themeID: nil, visibleLayers: [.background, .slide, .props]),
        lobby: ScreenLook(themeID: nil, visibleLayers: [.background, .slide, .props])])

    func liveState() -> ShowState {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Amazing grace")])))
        state.apply(.trigger(index: 0))
        return state
    }

    // MARK: Resolution (pure)

    @Test func aScreenWithItsOwnLookUsesItAndOthersFollowTheShowsLook() {
        let profiles = Self.profiles(lobbyLook: Self.worship.id)
        let looks = [Self.sermon, Self.worship]
        #expect(ScreenLooks.look(for: profiles[1], global: Self.sermon, looks: looks)?.id == Self.worship.id)
        #expect(ScreenLooks.look(for: profiles[0], global: Self.sermon, looks: looks)?.id == Self.sermon.id)
        let overrides = ScreenLooks.overrides(profiles: profiles, global: Self.sermon, looks: looks)
        #expect(overrides.keys.sorted { $0.uuidString < $1.uuidString } == [Self.lobby])
    }

    @Test func aLookThatDoesNotExistAnymoreFallsBackToTheShowsLook() {
        let profiles = Self.profiles(lobbyLook: UUID())
        #expect(ScreenLooks.look(for: profiles[1], global: Self.sermon, looks: [Self.sermon])?.id == Self.sermon.id)
        #expect(ScreenLooks.overrides(profiles: profiles, global: Self.sermon, looks: [Self.sermon]).isEmpty)
    }

    @Test func aScreenWhoseOwnLookIsTheShowsLookNeedsNoOverride() {
        let profiles = Self.profiles(lobbyLook: Self.sermon.id)
        #expect(ScreenLooks.overrides(profiles: profiles, global: Self.sermon, looks: [Self.sermon]).isEmpty)
    }

    @Test func theSummaryNamesWhichLookAppliesAndWhy() {
        let profiles = Self.profiles(lobbyLook: Self.worship.id)
        let looks = [Self.sermon, Self.worship]
        let own = ScreenLooks.summary(for: profiles[1], global: Self.sermon, looks: looks)
        #expect(own.lookName == "Worship" && own.isOwn)
        let followed = ScreenLooks.summary(for: profiles[0], global: Self.sermon, looks: looks)
        #expect(followed.lookName == "Sermon" && !followed.isOwn)
        let dangling = ScreenLooks.summary(for: Self.profiles(lobbyLook: UUID())[1], global: Self.sermon, looks: looks)
        #expect(dangling.lookName == "Sermon" && !dangling.isOwn)
    }

    // MARK: Composition

    @Test func theComposedSceneUsesTheScreensOwnLookAndTheOtherFollowsTheGlobalOne() {
        let profiles = Self.profiles(lobbyLook: Self.worship.id)
        let looks = [Self.sermon, Self.worship]
        let overrides = ScreenLooks.overrides(profiles: profiles, global: Self.sermon, looks: looks)
        let snapshot = PublishedScenes(state: liveState(), clockText: nil, profiles: profiles, look: Self.sermon, screenLooks: overrides)
        let global = PublishedScenes(state: liveState(), clockText: nil, profiles: profiles, look: Self.sermon)
        let alone = PublishedScenes(state: liveState(), clockText: nil, profiles: profiles, look: Self.worship)
        #expect(snapshot.scene(forScreen: Self.audience) == global.scene(forScreen: Self.audience))     // follows the show's Look
        #expect(snapshot.scene(forScreen: Self.lobby) == alone.scene(forScreen: Self.lobby))             // its own Look
        #expect(snapshot.scene(forScreen: Self.lobby) != global.scene(forScreen: Self.lobby))
    }

    @Test func anEmptyOverrideMapComposesExactlyAsNoMap() {
        let a = PublishedScenes(state: liveState(), clockText: "10:30", profiles: Self.profiles(), look: Self.sermon)
        let b = PublishedScenes(state: liveState(), clockText: "10:30", profiles: Self.profiles(), look: Self.sermon, screenLooks: [:])
        #expect(a == b)
    }

    @Test func imagePathsInUseFollowTheLookEachScreenUses() {
        let logo = Prop(name: "Logo", imagePath: "/pictures/logo.png", frame: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1))
        let showsProps = Look(id: UUID(), name: "Props", screens: [Self.audience: ScreenLook(visibleLayers: [.slide, .props]),
                                                                    Self.lobby: ScreenLook(visibleLayers: [.slide, .props])])
        let noProps = Look(id: UUID(), name: "None", screens: [Self.audience: ScreenLook(visibleLayers: [.slide]), Self.lobby: ScreenLook(visibleLayers: [.slide])])
        let profiles = Self.profiles(lobbyLook: noProps.id)
        let looks = [showsProps, noProps]
        let overrides = ScreenLooks.overrides(profiles: profiles, global: showsProps, looks: looks)
        // The Sanctuary follows the show's Look and draws the logo; the Lobby has its own Look without props.
        let paths = ImageUsage.pathsInUse(props: [logo], themes: Theme.builtIn, profiles: profiles, look: showsProps, presentationThemeID: nil, screenLooks: overrides)
        #expect(paths == ["/pictures/logo.png"])
        let lobbyOnly = [profiles[1]]
        let none = ImageUsage.pathsInUse(props: [logo], themes: Theme.builtIn, profiles: lobbyOnly, look: showsProps, presentationThemeID: nil, screenLooks: overrides)
        #expect(none.isEmpty)
    }

    // MARK: Settings model

    func loaded(_ profiles: [ScreenProfile] = UI007f_ScreenLookTests.profiles()) async throws -> (SettingsModel, LibraryStore) {
        let store = try LibraryStore.inMemory()
        let settings = SettingsModel(store: store, legacy: nil, defaultProfiles: { profiles })
        await settings.load()
        return (settings, store)
    }

    @Test func choosingALookForAScreenIsExplicitAndLeavesOtherScreensAlone() async throws {
        let (settings, _) = try await loaded()
        let global = try #require(settings.currentLook)
        #expect(settings.profiles.allSatisfy { $0.screenLookID == nil })        // nothing is chosen until the operator chooses
        let other = settings.addLook()
        settings.selectLook(global.id)
        settings.setScreenLook(other.id, forScreen: Self.lobby)
        #expect(settings.profiles.first { $0.id == Self.lobby }?.screenLookID == other.id)
        #expect(settings.profiles.first { $0.id == Self.audience }?.screenLookID == nil)
        #expect(settings.screenLookOverrides.keys.contains(Self.lobby) && settings.screenLookOverrides.count == 1)
        #expect(settings.currentLook?.id == global.id)
    }

    @Test func changingTheShowsLookDoesNotMoveAScreenThatHasItsOwn() async throws {
        let (settings, _) = try await loaded()
        let first = try #require(settings.currentLook)
        let second = settings.addLook()
        settings.setTheme(Theme.lowerThirdID, forScreen: Self.lobby)         // the second Look themes the Lobby
        settings.selectLook(first.id)
        settings.setScreenLook(second.id, forScreen: Self.lobby)
        let before = settings.screenLook(for: Self.lobby)
        #expect(before.themeID == Theme.lowerThirdID)
        settings.selectLook(second.id)
        settings.selectLook(first.id)
        #expect(settings.screenLook(for: Self.lobby) == before)
        #expect(settings.screenLook(for: Self.audience) == first.screenLook(for: Self.audience, in: settings.profiles))
    }

    @Test func aChoiceTakesEffectThroughTheSamePublishAsSelectingALook() async throws {
        let (settings, _) = try await loaded()
        let first = try #require(settings.currentLook)
        let second = settings.addLook()
        settings.selectLook(first.id)
        var appearance = 0, profiles = 0
        settings.onAppearanceChange = { appearance += 1 }
        settings.onProfilesChange = { profiles += 1 }
        settings.setScreenLook(second.id, forScreen: Self.lobby)
        #expect(appearance == 1 && profiles == 0)              // one republish, no output re-plan, as selectLook
        settings.setScreenLook(second.id, forScreen: Self.lobby)
        #expect(appearance == 1)                               // no change, no publish
        settings.selectLook(second.id)
        #expect(appearance == 2)
        settings.setScreenLook(nil, forScreen: Self.lobby)
        #expect(appearance == 3 && settings.profiles.first { $0.id == Self.lobby }?.screenLookID == nil)
    }

    @Test func aLookThatDoesNotExistCannotBeChosen() async throws {
        let (settings, _) = try await loaded()
        var appearance = 0
        settings.onAppearanceChange = { appearance += 1 }
        settings.setScreenLook(UUID(), forScreen: Self.lobby)
        settings.setScreenLook(settings.currentLook?.id, forScreen: UUID())
        #expect(appearance == 0 && settings.profiles.allSatisfy { $0.screenLookID == nil })
    }

    @Test func deletingALookFallsBackToTheShowsLookAndIsRemembered() async throws {
        let (settings, store) = try await loaded()
        let first = try #require(settings.currentLook)
        let second = settings.addLook()
        settings.selectLook(first.id)
        settings.setScreenLook(second.id, forScreen: Self.lobby)
        var appearance = 0
        settings.onAppearanceChange = { appearance += 1 }
        settings.deleteLook(second.id)
        #expect(settings.profiles.first { $0.id == Self.lobby }?.screenLookID == nil)
        #expect(settings.screenLookOverrides.isEmpty && appearance == 1)
        await settings.flush()
        #expect(try await store.screenProfiles().first { $0.id == Self.lobby }?.screenLookID == nil)
    }

    @Test func theChoiceSurvivesARelaunch() async throws {
        let (settings, store) = try await loaded()
        let first = try #require(settings.currentLook)
        let second = settings.addLook()
        settings.selectLook(first.id)
        settings.setScreenLook(second.id, forScreen: Self.lobby)
        await settings.flush()
        let again = SettingsModel(store: store, legacy: nil, defaultProfiles: { Self.profiles() })
        await again.load()
        #expect(again.profiles.first { $0.id == Self.lobby }?.screenLookID == second.id)
        #expect(again.currentLook?.id == first.id)
    }

    @Test func editingAScreensThemeEditsTheLookThatScreenUses() async throws {
        let (settings, _) = try await loaded()
        let first = try #require(settings.currentLook)
        let second = settings.addLook()
        settings.selectLook(first.id)
        settings.setScreenLook(second.id, forScreen: Self.lobby)
        settings.setTheme(Theme.lowerThirdID, forScreen: Self.lobby)
        #expect(settings.looks.first { $0.id == second.id }?.screens[Self.lobby]?.themeID == Theme.lowerThirdID)
        #expect(settings.looks.first { $0.id == first.id }?.screens[Self.lobby]?.themeID == nil)
    }

    @Test func aStageScreenOnlyTakesTheLookForItsProps() {
        // A stage screen's own layout is composed by the stage model; the Look decides only which props sit on top, as under the show's Look.
        let profiles = Self.profiles()
        let overrides = [Self.stage: Look(id: UUID(), name: "Hide", screens: [Self.stage: ScreenLook(visibleLayers: [.slide])])]
        let prop = Prop(name: "Strap", imagePath: "", frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.1), targets: [.stage],
                        kind: .text, text: TextPropSpec(text: "Hello"))
        let withLook = PublishedScenes(state: liveState(), clockText: nil, profiles: profiles, look: Self.sermon, props: [prop], screenLooks: overrides)
        let global = PublishedScenes(state: liveState(), clockText: nil, profiles: profiles, look: Self.sermon, props: [prop])
        #expect(withLook.scene(forScreen: Self.stage).textLayers.count < global.scene(forScreen: Self.stage).textLayers.count
                || withLook.scene(forScreen: Self.stage) != global.scene(forScreen: Self.stage))
    }

    // MARK: Digest: a library with no per-screen Look

    @Test func noPerScreenLookGivesTheScenesRecordedBeforeUI007fForAudienceStageAndKeyedBroadcast() throws {
        let plain = try UI007f_ScenesDigestTests.replay()
        let withEmpty = try UI007f_ScenesDigestTests.replay(overrides: true)
        #expect(plain.digest == UI007f_ScenesDigestTests.recordedDigest)
        #expect(withEmpty.digest == UI007f_ScenesDigestTests.recordedDigest && withEmpty.publications == plain.publications)
    }
}
