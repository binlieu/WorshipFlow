// UI-007e: the Stage Section elements (the live slide's section and the next slide's section). Written before the code.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI007e_StageSectionTests {
    let names: [String?] = ["Verse 1", "Verse 1", "Chorus", nil]

    func live(at index: Int = 0, names: [String?]? = nil) -> ShowState {
        var state = ShowState()
        let slides = (0..<4).map { SlideContent(primary: "Line \($0)") }
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: slides, sectionNames: names ?? self.names)))
        state.apply(.trigger(index: index))
        return state
    }

    func layout(_ templates: [NewStageElement]) throws -> StageLayout {
        StageLayout(id: UUID(), name: "s", background: .black, elements: try templates.map { try #require(StageEditing.newElement($0, timerID: nil)) })
    }

    func texts(_ layout: StageLayout, _ state: ShowState) -> [String] {
        StageComposer.scene(layout: layout, context: StageContext(state: state, now: 0, timeOfDayText: "9:00", timers: [], message: nil, notes: nil)).textLayers.map(\.text)
    }

    @Test func theSectionElementDrawsTheLiveSlidesSection() throws {
        let l = try layout([.sectionName])
        #expect(texts(l, live(at: 0)) == ["Verse 1"])
        #expect(texts(l, live(at: 2)) == ["Chorus"])
    }

    @Test func aSlideInNoSectionDrawsNothing() throws {
        #expect(texts(try layout([.sectionName]), live(at: 3)).isEmpty)
        #expect(texts(try layout([.sectionName]), live(names: [])).isEmpty)      // a deck built without sections
    }

    @Test func nothingIsDrawnWhileStopped() throws {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "a")], sectionNames: ["Verse 1"])))
        #expect(texts(try layout([.sectionName, .nextSectionName]), state).isEmpty)
    }

    @Test func theSectionIsKeptWhileTheWordsAreCleared() throws {
        var state = live(at: 2)
        state.apply(.clear)
        #expect(texts(try layout([.sectionName]), state) == ["Chorus"])
    }

    @Test func theNextSectionDrawsOnlyWhenTheNextSlideIsInADifferentSection() throws {
        let l = try layout([.nextSectionName])
        #expect(texts(l, live(at: 0)).isEmpty)                 // next slide is still Verse 1
        #expect(texts(l, live(at: 1)) == ["NEXT", "Chorus"])    // the caption, then the name
        #expect(texts(l, live(at: 2)).isEmpty)                 // next slide is in no section
        #expect(texts(l, live(at: 3)).isEmpty)                 // no next slide
    }

    @Test func aHiddenSectionElementDrawsNothing() throws {
        var l = try layout([.sectionName, .nextSectionName])
        for i in l.elements.indices { l.elements[i].isHidden = true }
        #expect(texts(l, live(at: 1)).isEmpty)
    }

    @Test func theSectionNameNeverReachesAnAudienceOrBroadcastScene() {
        let state = live(at: 1)
        for role in [ScreenRole.audience, .broadcast] {
            let scene = SceneComposer.scene(for: role, state: state, theme: role == .audience ? Theme.fullScreen : Theme.lowerThird, look: .standard, props: [])
            #expect(!scene.textLayers.map(\.text).contains { $0.contains("Verse 1") || $0.contains("Chorus") })
        }
        // the built-in stage layout has no Section element: only a layout the operator added one to shows it
        #expect(!texts(.standard, state).contains("Verse 1"))
    }

    @Test func theElementsHavePresetPositionsOnScreenAndNeitherTicks() throws {
        for template in [NewStageElement.sectionName, .nextSectionName] {
            let e = try #require(StageEditing.newElement(template, timerID: nil))
            #expect(e.frame.x >= 0 && e.frame.y >= 0 && e.frame.x + e.frame.width <= 1 && e.frame.y + e.frame.height <= 1)
            #expect(!e.kind.ticks)
        }
        #expect(!StageEditing.needsPerSecondRefresh(try layout([.sectionName, .nextSectionName])))
        #expect(NewStageElement.sectionName.title == "Section" && NewStageElement.nextSectionName.title == "Next section")
    }

    @Test func theKindsRoundTripAndAnEarlierLayoutStillDecodes() throws {
        let l = try layout([.sectionName, .nextSectionName])
        let back = try JSONDecoder().decode(StageLayout.self, from: JSONEncoder().encode(l))
        #expect(back == l)
        let old = try JSONDecoder().decode(StageLayout.self, from: JSONEncoder().encode(StageLayout.standard))
        #expect(old == StageLayout.standard)
    }

    @Test func addingTheElementsPersistsThemInTheOperatorsLayout() async throws {
        let store = try LibraryStore.inMemory()
        let stage = StageModel(store: store)
        await stage.load()
        let made = try #require(stage.createLayout(name: "Mine"))
        let a = try #require(stage.addElement(.sectionName, to: made.id))
        let b = try #require(stage.addElement(.nextSectionName, to: made.id))
        #expect(a != b)
        let kinds = try #require(stage.layout(withID: made.id)).elements.map(\.kind)
        #expect(kinds.contains(.sectionName) && kinds.contains(.nextSectionName))
        stage.setHidden(true, for: a, in: made.id)
        #expect(try #require(stage.layout(withID: made.id)).elements.first { $0.id == a }?.isHidden == true)
        // the built-in layout refuses
        #expect(stage.addElement(.sectionName, to: StageLayout.standardID) == nil)
    }

    @Test func theEditorsSampleSceneShowsTheSections() throws {
        let l = try layout([.sectionName, .nextSectionName])
        let drawn = StageEditing.sampleScene(layout: l, timers: [], now: 0).textLayers.map(\.text)
        #expect(drawn.contains(StageEditing.sampleLines.currentSection))
        #expect(drawn.contains(StageEditing.sampleLines.nextSection))
    }
}
