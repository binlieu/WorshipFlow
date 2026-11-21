// UI-005b item 5: per-prop targets and text props through the settings model, and the published scenes that carry them to the screens.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI005b_PropsModelTests {
    func loaded() async throws -> (SettingsModel, LibraryStore) {
        let store = try LibraryStore.inMemory()
        let settings = SettingsModel(store: store, legacy: nil, defaultProfiles: SettingsModelTests.defaults)
        await settings.load()
        return (settings, store)
    }
    let logo = Prop(name: "Church logo bug", imagePath: "/p/logo.png", frame: NormalizedRect(x: 0.85, y: 0.05, width: 0.1, height: 0.1))

    @Test func aTargetIsSwitchedOnAndOffAndStored() async throws {
        let (settings, store) = try await loaded()
        var redraws = 0
        settings.onAppearanceChange = { redraws += 1 }
        settings.addProp(logo, bookmark: nil)
        #expect(settings.props.first?.targets == [.audience, .broadcast])
        redraws = 0
        settings.setProp(logo.id, target: .stage, isOn: true)
        #expect(settings.props.first?.targets == [.audience, .stage, .broadcast] && redraws == 1)
        settings.setProp(logo.id, target: .broadcast, isOn: false)
        #expect(settings.props.first?.targets == [.audience, .stage])
        settings.setProp(logo.id, target: .stage, isOn: true)            // already on: nothing to do
        #expect(redraws == 2)
        settings.setProp(UUID(), target: .stage, isOn: true)             // a prop that is not there: nothing happens
        #expect(redraws == 2)
        await settings.flush()
        #expect(try await store.props().first?.targets == [.audience, .stage])
        #expect(settings.props.first?.isOn == true && settings.props.first?.imagePath == "/p/logo.png")   // the rest is untouched
    }

    @Test func aTextPropIsAddedEditedStoredAndRemoved() async throws {
        let (settings, store) = try await loaded()
        let spec = TextPropSpec(text: "Ân điển lạ lùng — Bài giảng", fontSize: 54, colorHex: "#FFD17B", anchor: .bottomLeft)
        let strap = try #require(settings.addTextProp(name: "Service title strap", spec: spec, targets: [.broadcast]))
        #expect(strap.kind == .text && strap.targets == [.broadcast] && strap.text == spec)
        await settings.flush()
        #expect(try await store.props().first == strap)                    // the stored prop is the same value, words and all
        settings.updateTextProp(strap.id, name: "Speaker name", spec: TextPropSpec(text: "Mục sư Nguyễn Văn An", fontSize: 40, colorHex: "#FFFFFF", anchor: .topRight))
        await settings.flush()
        let stored = try #require(try await store.props().first)
        #expect(stored.name == "Speaker name" && stored.text?.text == "Mục sư Nguyễn Văn An" && stored.text?.anchor == .topRight && stored.targets == [.broadcast])
        settings.removeProp(strap.id)
        await settings.flush()
        #expect(try await store.props().isEmpty)
    }

    @Test func aTextPropNeedsANameAndAPictureOneIsNotEditedAsText() async throws {
        let (settings, _) = try await loaded()
        #expect(settings.addTextProp(name: "   ", spec: TextPropSpec(text: "x"), targets: [.audience]) == nil)
        #expect(settings.lastError != nil && settings.props.isEmpty)
        settings.addProp(logo, bookmark: nil)
        settings.updateTextProp(logo.id, name: "Changed", spec: TextPropSpec(text: "x"))
        #expect(settings.props.first == logo)                               // a picture prop is not turned into text
    }

    @Test func publishedScenesCarryEachPropOnlyToItsTargetedRoles() {
        let audience = ScreenProfile(name: "A", role: .audience, destination: .window)
        let stage = ScreenProfile(name: "S", role: .stage, destination: .window)
        let broadcast = ScreenProfile(name: "B", role: .broadcast, destination: .window)
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Words")])))
        state.apply(.trigger(index: 0))
        let strap = Prop(name: "Strap", imagePath: "", frame: .full, targets: [.stage], kind: .text, text: TextPropSpec(text: "Ân điển"))
        let badge = Prop(name: "Badge", imagePath: "/p/b.png", frame: .full, targets: [.broadcast])
        let base = SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: [])
        let scenes = PublishedScenes(state: state, clockText: nil, profiles: [audience, stage, broadcast], props: [strap, badge],
                                     stageScenes: [stage.id: base])
        #expect(scenes.scene(forScreen: stage.id).textLayers.map(\.text) == ["Ân điển"] && scenes.scene(forScreen: stage.id).overlayImages.isEmpty)
        #expect(!scenes.scene(forScreen: audience.id).textLayers.map(\.text).contains("Ân điển") && scenes.scene(forScreen: audience.id).overlayImages.isEmpty)
        #expect(!scenes.scene(forScreen: broadcast.id).textLayers.map(\.text).contains("Ân điển"))
        #expect(scenes.scene(forScreen: broadcast.id).overlayImages.map(\.path) == ["/p/b.png"])
    }

    @Test func aStageScreenWithNoPropsForItIsExactlyWhatItWas() {
        let stage = ScreenProfile(name: "S", role: .stage, destination: .window)
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Words")])))
        state.apply(.trigger(index: 0))
        let ready = SceneDescription(backgroundColor: .black, showsVideo: false, textLayers: [])
        let old = Prop(name: "Old logo", imagePath: "/p/l.png", frame: .full)             // a prop made before v12: audience and broadcast
        let scenes = PublishedScenes(state: state, clockText: nil, profiles: [stage], props: [old], stageScenes: [stage.id: ready])
        #expect(scenes.scene(forScreen: stage.id) == ready)
    }
}
