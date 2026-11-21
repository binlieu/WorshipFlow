// CUE-002a (AUTO-01): slide actions in the library file. Written by the implementer.
import Testing
import Foundation
import GRDB
import Domain
import CueEngine
@_spi(CueStore) import Persistence
import CueStore

@Suite struct CueStoreSlideActionTests {
    @Test func setsAndGetsAndAnEmptyListRemovesTheRow() async throws {
        let f = try Fixture()
        let s = try #require(try await f.slides(["one"]).first)
        let look = UUID()
        #expect(try await f.store.slideActions(for: s.id).isEmpty)
        try await f.store.setSlideActions([.selectLook(look), .wait(seconds: 2)], for: s.id)
        #expect(try await f.store.slideActions(for: s.id) == [.selectLook(look), .wait(seconds: 2)])
        try await f.store.setSlideActions([.selectLook(look)], for: s.id)
        #expect(try await f.rawCount("cueSlideActions") == 1)
        try await f.store.setSlideActions([], for: s.id)
        #expect(try await f.rawCount("cueSlideActions") == 0)
    }

    @Test func transportIsRefusedDirectlyAndThroughANestedMacroAndNothingIsWritten() async throws {
        let f = try Fixture()
        let s = try #require(try await f.slides(["one"]).first)
        let inner = macro("Inner", [.transport(.next)]), outer = macro("Outer", [.runMacro(inner.id)])
        try await f.store.saveMacro(inner)
        try await f.store.saveMacro(outer)
        let direct = await #expect(throws: CueStoreError.self) { try await f.store.setSlideActions([.transport(.next)], for: s.id) }
        guard case .invalidSlideActions(let errors)? = direct else { Issue.record("wrong error"); return }
        #expect(errors == [.transportNotAllowed(.next)])
        let nested = await #expect(throws: CueStoreError.self) { try await f.store.setSlideActions([.runMacro(outer.id)], for: s.id) }
        guard case .invalidSlideActions(let nestedErrors)? = nested else { Issue.record("wrong error"); return }
        #expect(nestedErrors == [.macroContainsTransport(macroName: "Outer", transport: .next)])
        #expect(try await f.rawCount("cueSlideActions") == 0)
    }

    @Test func aMacroThatDoesNotExistAndASlideThatDoesNotExistAreRefused() async throws {
        let f = try Fixture()
        let s = try #require(try await f.slides(["one"]).first)
        let missing = UUID()
        await #expect(throws: CueStoreError.unknownMacro(missing)) { try await f.store.setSlideActions([.runMacro(missing)], for: s.id) }
        await #expect(throws: CueStoreError.notFound) { try await f.store.setSlideActions([.selectLook(UUID())], for: UUID()) }
        #expect(try await f.rawCount("cueSlideActions") == 0)
    }

    @Test func deletingTheSlideOrThePresentationRemovesItsActions() async throws {
        let f = try Fixture()
        let slides = try await f.slides(["one", "two"])
        for s in slides { try await f.store.setSlideActions([.selectLook(UUID())], for: s.id) }
        try await f.library.deleteSlide(id: slides[0].id)
        #expect(try await f.rawCount("cueSlideActions") == 1)
        try await f.library.deletePresentation(id: slides[1].presentationID)
        #expect(try await f.rawCount("cueSlideActions") == 0)
    }

    @Test func actionsSurviveAReflowForSlidesWhoseWordsDidNotChange() async throws {
        let f = try Fixture()
        let lib = try await f.library.createLibrary(name: "Songs")
        let p = try await f.library.createPresentation(in: lib.id, title: "Song", kind: .song)
        func reflowed(_ text: String) -> [ReflowResult] { Reflow.contents(primary: text, secondary: nil, maxLines: 1) }
        try await f.library.replaceContent(of: p.id, with: reflowed("Verse 1\na\nb\n\nChorus\nc"))
        let before = try await f.library.slides(of: p.id)
        let lookB = UUID(), lookC = UUID(), lookA = UUID()
        try await f.store.setSlideActions([.selectLook(lookA)], for: before[0].id)
        try await f.store.setSlideActions([.selectLook(lookB)], for: before[1].id)
        try await f.store.setSlideActions([.selectLook(lookC)], for: before[2].id)

        try await f.library.replaceContent(of: p.id, with: reflowed("Verse 1\na edited\nb\n\nChorus\nc\n\nBridge\nd"))
        let after = try await f.library.slides(of: p.id)
        #expect(try await f.store.slideActions(for: after[0].id).isEmpty)       // words changed
        #expect(try await f.store.slideActions(for: after[1].id) == [.selectLook(lookB)])
        #expect(try await f.store.slideActions(for: after[2].id) == [.selectLook(lookC)])
        #expect(try await f.store.slideActions(for: after[3].id).isEmpty)
        #expect(try await f.rawCount("cueSlideActions") == 2)                   // nothing left pointing at a vanished slide
    }

    @Test func aStoreOpenedBeforeTheCueTablesExistSaysSoInsteadOfCrashing() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wf-cue002a-\(UUID().uuidString)/L.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = try LibraryStore.open(at: url, migratingUpTo: "v8")
        let store = CueStore(library: old)
        await #expect(throws: CueStoreError.libraryNeedsUpdate) { _ = try await store.macros() }
        await #expect(throws: CueStoreError.libraryNeedsUpdate) { _ = try await store.loadLibrary() }
        try old.close()
    }
}
