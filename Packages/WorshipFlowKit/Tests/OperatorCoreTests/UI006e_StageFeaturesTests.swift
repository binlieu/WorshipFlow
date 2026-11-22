// UI-006e: the Stage features the design draws and the app lacked: hide an element (the eye), Auto-fit, the second-language colour and the
// Band / Speaker / Clock only presets. Written before the code.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI006e_StageFeaturesTests {
    func ready(_ store: LibraryStore? = nil) async throws -> (StageModel, LibraryStore) {
        let store = try store ?? LibraryStore.inMemory()
        let model = StageModel(store: store)
        await model.load()
        return (model, store)
    }

    func live(_ primary: String, secondary: String? = nil, next: String? = nil) -> ShowState {
        var state = ShowState()
        var slides = [SlideContent(primary: primary, secondary: secondary)]
        if let next { slides.append(SlideContent(primary: next)) }
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: slides)))
        state.apply(.trigger(index: 0))
        return state
    }

    func scene(_ layout: StageLayout, message: String? = nil, notes: String? = nil, state: ShowState? = nil) -> SceneDescription {
        let context = StageContext(state: state ?? live("Amazing grace", secondary: "Ân điển", next: "How sweet"), now: 0, timeOfDayText: "9:14 AM",
                                   timers: [], message: message, notes: notes)
        return StageComposer.scene(layout: layout, context: context)
    }

    // MARK: Hide (the eye)

    @Test func aHiddenElementDrawsNothingAndTheOthersStay() throws {
        var layout = StageLayout.standard
        let before = scene(layout).textLayers.map(\.text)
        #expect(before.contains("Amazing grace"))
        let i = try #require(layout.elements.firstIndex { $0.kind == .currentSlide })
        layout.elements[i].isHidden = true
        let after = scene(layout).textLayers.map(\.text)
        #expect(!after.contains("Amazing grace") && !after.contains("Ân điển"))
        #expect(after.contains("How sweet") && after.contains("9:14 AM"))
    }

    @Test func aHiddenMessageElementStillLetsTheMessageReachTheStage() throws {
        var layout = StageLayout(id: UUID(), name: "m", background: .black, elements: [
            try #require(StageEditing.newElement(.message, timerID: nil))])
        #expect(scene(layout, message: "Wrap up").textLayers.map(\.text) == ["Wrap up"])
        layout.elements[0].isHidden = true
        // the message is never silently lost: with the element hidden it comes as the banner a layout without a message element gets
        #expect(scene(layout, message: "Wrap up").textLayers.map(\.text) == ["Wrap up"])
        #expect(scene(layout, message: "Wrap up").textLayers.first?.style.fontSize == 64)      // the banner, not the 56-point message element
    }

    @Test func hiddenNotesDoNotDrawOnTheStage() throws {
        var layout = StageLayout(id: UUID(), name: "n", background: .black, elements: [
            try #require(StageEditing.newElement(.notes, timerID: nil))])
        #expect(scene(layout, notes: "Pause here").textLayers.map(\.text) == ["Pause here"])
        layout.elements[0].isHidden = true
        #expect(scene(layout, notes: "Pause here").textLayers.isEmpty)
    }

    @Test func layoutsSavedBeforeTheseFieldsLoadVisibleAndNotFitted() throws {
        let element = try #require(StageEditing.newElement(.nextSlide, timerID: nil))
        let data = try JSONEncoder().encode(element)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "isHidden")
        json.removeValue(forKey: "autoFit")
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(StageElement.self, from: old)
        #expect(!decoded.isHidden && !decoded.autoFit && decoded == element)
    }

    @Test func hideAndAutoFitSurviveARoundTripThroughTheLibrary() async throws {
        let (model, store) = try await ready()
        let layout = try #require(model.createLayout(name: "Round"))
        let id = try #require(layout.elements.first?.id)
        model.setHidden(true, for: id, in: layout.id)
        model.setAutoFit(true, for: id, in: layout.id)
        await model.flush()
        let again = StageModel(store: store)
        await again.load()
        let e = try #require(again.layout(withID: layout.id)?.elements.first { $0.id == id })
        #expect(e.isHidden && e.autoFit)
    }

    @Test func theBuiltInLayoutCannotBeHiddenOrFitted() async throws {
        let (model, _) = try await ready()
        let id = try #require(StageLayout.standard.elements.first?.id)
        model.setHidden(true, for: id, in: StageLayout.standardID)
        #expect(model.lastError == StageModel.readOnlyMessage)
        model.dismissError()
        model.setAutoFit(true, for: id, in: StageLayout.standardID)
        #expect(model.lastError == StageModel.readOnlyMessage)
        #expect(StageLayout.standard.elements.allSatisfy { !$0.isHidden && !$0.autoFit })
    }

    @Test func settingTheSameValueWritesNothingAndHidingDoesNotChangeTheFrame() async throws {
        let (model, _) = try await ready()
        let layout = try #require(model.createLayout(name: "Same"))
        let e = try #require(layout.elements.first)
        var calls = 0
        model.onChange = { calls += 1 }
        model.setHidden(false, for: e.id, in: layout.id)
        #expect(calls == 0)
        model.setHidden(true, for: e.id, in: layout.id)
        #expect(calls == 1 && model.layout(withID: layout.id)?.elements.first?.frame == e.frame)
    }

    // MARK: Auto-fit

    @Test func autoFitGivesTheLyricTheDesignsMinimumAsItsFloor() throws {
        var layout = StageLayout.standard
        #expect(scene(layout).textLayers.allSatisfy { $0.fitFloor == nil })
        let i = try #require(layout.elements.firstIndex { $0.kind == .currentSlide })
        layout.elements[i].autoFit = true
        let layers = scene(layout).textLayers
        let lyric = try #require(layers.first { $0.text == "Amazing grace" })
        #expect(lyric.fitFloor == 64)
        // the second-language line shrinks with it, by the same factor: its floor is in the same ratio as its size
        let second = try #require(layers.first { $0.text == "Ân điển" })
        let ratio = layout.elements[i].secondLanguage.map { $0.style.fontSize / layout.elements[i].style.fontSize } ?? 0
        #expect(abs((second.fitFloor ?? 0) / 64 - ratio) < 1e-9)
        #expect(layers.filter { $0.fitFloor != nil }.count == 2)
    }

    @Test func autoFitNeverRaisesASizeAndFloorsOtherElementsAtHalf() throws {
        var small = try #require(StageEditing.newElement(.currentSlide, timerID: nil))
        small.style.fontSize = 40
        #expect(StageAutoFit.floor(for: small) == 40)         // already below the lyric minimum: left as set
        #expect(StageAutoFit.isBelowLyricMinimum(small))
        small.style.fontSize = 64
        #expect(!StageAutoFit.isBelowLyricMinimum(small))
        var notes = try #require(StageEditing.newElement(.notes, timerID: nil))
        notes.style.fontSize = 80
        #expect(StageAutoFit.floor(for: notes) == 40)
        notes.style.fontSize = 30
        #expect(StageAutoFit.floor(for: notes) == 24)
        notes.style.fontSize = 20
        #expect(StageAutoFit.floor(for: notes) == 20)
        var clock = try #require(StageEditing.newElement(.timeOfDay, timerID: nil))
        clock.style.fontSize = 100
        #expect(!StageAutoFit.isBelowLyricMinimum(clock))
    }

    @Test func autoFitOnAHiddenElementAddsNothing() throws {
        var layout = StageLayout.standard
        let i = try #require(layout.elements.firstIndex { $0.kind == .currentSlide })
        layout.elements[i].autoFit = true
        layout.elements[i].isHidden = true
        #expect(scene(layout).textLayers.allSatisfy { $0.fitFloor == nil })
    }

    // MARK: Second-language colour

    @Test func theSecondLanguageColourChangesOnlyThatLine() async throws {
        let (model, _) = try await ready()
        let layout = try #require(model.duplicateLayout(StageLayout.standardID))
        let e = try #require(layout.elements.first { $0.kind == .currentSlide })
        let green = ColorRGBA(red: 0, green: 1, blue: 0)
        model.setSecondLanguageColor(green, for: e.id, in: layout.id)
        let now = try #require(model.layout(withID: layout.id)?.elements.first { $0.id == e.id })
        #expect(now.secondLanguage?.style.color == green)
        #expect(now.style == e.style && now.secondLanguage?.relativeFrame == e.secondLanguage?.relativeFrame)
        let layers = model.scene(layout: model.layout(withID: layout.id) ?? layout, state: live("Hi", secondary: "Chào"), notes: nil).textLayers
        #expect(layers.first { $0.text == "Chào" }?.style.color == green)
        #expect(layers.first { $0.text == "Hi" }?.style.color == e.style.color)
    }

    @Test func anElementWithoutItsOwnSecondLanguageLineHasNoSecondColour() async throws {
        let (model, _) = try await ready()
        let layout = try #require(model.createLayout(name: "Plain"))
        let id = try #require(model.addElement(.currentSlide, to: layout.id))
        #expect(model.layout(withID: layout.id)?.elements.first { $0.id == id }?.secondLanguage == nil)
        let before = model.layout(withID: layout.id)
        model.setSecondLanguageColor(ColorRGBA(red: 0, green: 1, blue: 0), for: id, in: layout.id)
        #expect(model.layout(withID: layout.id) == before)
    }

    // MARK: Presets

    @Test func presetsMakeTheDesignsThreeLayoutsAsTheOperatorsOwn() async throws {
        let (model, store) = try await ready()
        let kinds: [StagePreset: [StageElement.Kind]] = [
            .band: [.currentSlide, .nextSlide], .speaker: [.notes, .firstCountdown], .clockOnly: [.timeOfDay]]
        for preset in StagePreset.allCases {
            let made = try #require(model.addPreset(preset, named: preset.title))
            #expect(made.name == preset.title && model.isEditable(made.id))
            #expect(made.elements.map(\.kind) == kinds[preset])
            #expect(!made.elements.contains { $0.isHidden || $0.autoFit })
            #expect(Set(made.elements.map(\.id)).isDisjoint(with: StageLayout.standard.elements.map(\.id)))
        }
        #expect(model.customLayouts.count == 3)
        await model.flush()
        let again = StageModel(store: store)
        await again.load()
        #expect(again.customLayouts == model.customLayouts)
        #expect(model.lastError == nil)
    }

    @Test func presetElementsAreOnScreenAndNotesStayOnTheStageOnly() async throws {
        let (model, _) = try await ready()
        for preset in StagePreset.allCases {
            let made = try #require(model.addPreset(preset, named: "P \(preset.title)"))
            for e in made.elements {
                let f = e.frame
                #expect(f.x >= 0 && f.y >= 0 && f.x + f.width <= 1 + 1e-9 && f.y + f.height <= 1 + 1e-9)
                #expect(f.width >= StageElement.minimumSize && f.height >= StageElement.minimumSize)
                #expect(StageEditing.sanitized(e) == e)      // already inside what the compositor draws
            }
        }
        // the Speaker preset shows the notes on the stage screen
        let speaker = try #require(model.customLayouts.first { $0.name == "P Speaker" })
        #expect(scene(speaker, notes: "Point two").textLayers.contains { $0.text == "Point two" })
    }

    @Test func aPresetNeedsAName() async throws {
        let (model, _) = try await ready()
        #expect(model.addPreset(.band, named: "   ") == nil)
        #expect(model.lastError != nil && model.customLayouts.isEmpty)
    }

    @Test func clockOnlyShowsOnlyTheClockAndStillGetsAMessage() async throws {
        let (model, _) = try await ready()
        let made = try #require(model.addPreset(.clockOnly, named: "Clock"))
        let texts = scene(made, message: "Hello").textLayers.map(\.text)
        #expect(texts.contains("9:14 AM") && texts.contains("Hello") && !texts.contains("Amazing grace"))
    }
}
