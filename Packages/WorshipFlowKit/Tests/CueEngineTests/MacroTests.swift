// CUE-001 (AUTO-02): macros and the macro library.
import Testing
import Foundation
@testable import CueEngine

private func macro(_ name: String, _ steps: [CueAction], id: UUID = UUID()) -> Macro {
    Macro(id: id, name: name, steps: steps)
}

@Suite struct MacroLibraryTests {
    @Test func savesAndFindsMacrosInOrder() throws {
        var lib = MacroLibrary()
        let a = macro("Intro", [.selectLook(UUID())])
        let b = macro("Outro", [.transport(.stop)])
        try lib.save(a)
        try lib.save(b)
        #expect(lib.macros.map(\.name) == ["Intro", "Outro"])
        #expect(lib.macro(id: a.id) == a)
        #expect(lib.macro(id: UUID()) == nil)
    }

    @Test func savingAgainReplacesInPlace() throws {
        var lib = MacroLibrary()
        let a = macro("A", [])
        try lib.save(a)
        try lib.save(macro("B", []))
        var a2 = a
        a2.name = "A renamed"
        try lib.save(a2)
        #expect(lib.macros.map(\.name) == ["A renamed", "B"])
    }

    @Test func removeDeletesAndReportsWhetherItExisted() throws {
        var lib = MacroLibrary()
        let a = macro("A", [])
        try lib.save(a)
        let first = lib.remove(id: a.id)
        let second = lib.remove(id: a.id)
        #expect(first)
        #expect(!second)
        #expect(lib.macros.isEmpty)
    }

    @Test func aBlankNameIsRejected() {
        var lib = MacroLibrary()
        #expect(throws: MacroLibraryError.emptyName) { try lib.save(macro("   ", [])) }
        #expect(lib.macros.isEmpty)
    }

    @Test func aMissingMacroIdIsAllowedAtSaveTime() throws {
        var lib = MacroLibrary()
        try lib.save(macro("Calls a ghost", [.runMacro(UUID())]))
        #expect(lib.macros.count == 1)
    }

    @Test func aMacroMayCallAnotherMacro() throws {
        var lib = MacroLibrary()
        let leaf = macro("Leaf", [.selectLook(UUID())])
        try lib.save(leaf)
        try lib.save(macro("Top", [.runMacro(leaf.id)]))
        #expect(lib.macros.count == 2)
    }

    @Test func aMacroCallingItselfIsACycleNamedInTheMessage() {
        var lib = MacroLibrary()
        let id = UUID()
        do {
            try lib.save(macro("Loop", [.runMacro(id)], id: id))
            Issue.record("expected a cycle error")
        } catch let e as MacroLibraryError {
            #expect(e == .cycle(["Loop", "Loop"]))
            #expect(e.message == "Macro cycle: Loop \u{2192} Loop")
        } catch { Issue.record("wrong error \(error)") }
        #expect(lib.macros.isEmpty)
    }

    @Test func aThreeMacroCycleIsRejectedWithTheWholePath() throws {
        var lib = MacroLibrary()
        let a = UUID(), b = UUID(), c = UUID()
        try lib.save(macro("B", [.runMacro(c)], id: b))
        try lib.save(macro("C", [.runMacro(a)], id: c))      // A does not exist yet: fine
        do {
            try lib.save(macro("A", [.runMacro(b)], id: a))
            Issue.record("expected a cycle error")
        } catch let e as MacroLibraryError {
            #expect(e == .cycle(["A", "B", "C", "A"]))
            #expect(e.message == "Macro cycle: A \u{2192} B \u{2192} C \u{2192} A")
        }
        #expect(lib.macros.map(\.name) == ["B", "C"])         // the failed save changed nothing
    }

    @Test func editingAnExistingMacroToCloseACycleIsRejectedAndKeepsTheOldVersion() throws {
        var lib = MacroLibrary()
        let a = UUID(), b = UUID()
        try lib.save(macro("A", [], id: a))
        try lib.save(macro("B", [.runMacro(a)], id: b))
        #expect(throws: MacroLibraryError.self) { try lib.save(macro("A", [.runMacro(b)], id: a)) }
        #expect(lib.macro(id: a)?.steps == [])
    }

    @Test func aDiamondIsNotACycle() throws {
        var lib = MacroLibrary()
        let leaf = macro("Leaf", [])
        let left = macro("Left", [.runMacro(leaf.id)])
        let right = macro("Right", [.runMacro(leaf.id)])
        try lib.save(leaf); try lib.save(left); try lib.save(right)
        try lib.save(macro("Top", [.runMacro(left.id), .runMacro(right.id)]))
        #expect(lib.macros.count == 4)
    }

    /// Builds a chain M1 -> M2 -> ... -> Mn (M1 on top) and returns the ids.
    private func chain(_ n: Int, into lib: inout MacroLibrary) throws -> [UUID] {
        let ids = (0..<n).map { _ in UUID() }
        for i in stride(from: n - 1, through: 0, by: -1) {
            let steps: [CueAction] = i == n - 1 ? [] : [.runMacro(ids[i + 1])]
            try lib.save(macro("M\(i + 1)", steps, id: ids[i]))
        }
        return ids
    }

    @Test func nestingEightDeepIsAllowed() throws {
        var lib = MacroLibrary()
        let ids = try chain(8, into: &lib)
        #expect(MacroLibrary.maxDepth == 8)
        #expect(lib.depth(of: ids[0]) == 8)     // ids[0] is M1, the top of the chain
        #expect(lib.depth(of: ids[7]) == 1)
    }

    @Test func nestingNineDeepIsRejectedAndNamesTheTopMacro() throws {
        var lib = MacroLibrary()
        let ids = try chain(8, into: &lib)
        // Extend the bottom of the chain: M8 now calls a new M9, which makes M1 nine levels deep.
        let m9 = macro("M9", [])
        try lib.save(m9)
        do {
            try lib.save(macro("M8", [.runMacro(m9.id)], id: ids[7]))
            Issue.record("expected a depth error")
        } catch let e as MacroLibraryError {
            #expect(e == .tooDeep(macro: "M1", depth: 9, limit: 8))
            #expect(e.message == "Macro \u{201C}M1\u{201D} would nest 9 levels deep; the limit is 8")
        }
        #expect(lib.macro(id: ids[7])?.steps == [])
    }

    @Test func depthCountsOnlyCallsNotWaitsOrOtherSteps() throws {
        var lib = MacroLibrary()
        let leaf = macro("Leaf", [.wait(seconds: 1), .selectLook(UUID()), .wait(seconds: 2)])
        try lib.save(leaf)
        #expect(lib.depth(of: leaf.id) == 1)
        #expect(lib.depth(of: UUID()) == 0)
    }

    @Test func libraryRoundTripsAsVersionedJSON() throws {
        var lib = MacroLibrary()
        let leaf = macro("Leaf", [.selectLook(UUID()), .wait(seconds: 1.5)])
        try lib.save(leaf)
        try lib.save(macro("Top", [.runMacro(leaf.id), .transport(.next)]))
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        let data = try e.encode(lib)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""version":1"#))
        #expect(try JSONDecoder().decode(MacroLibrary.self, from: data) == lib)
    }

    @Test func aFutureMacroStepSurvivesAsUnknown() throws {
        let text = #"{"macros":[{"id":"11111111-1111-1111-1111-111111111111","name":"M","steps":[{"kind":"dmx.set"}]}],"version":1}"#
        let lib = try JSONDecoder().decode(MacroLibrary.self, from: Data(text.utf8))
        #expect(lib.macros[0].steps == [.unknown(.object(["kind": .string("dmx.set")]))])
    }

    @Test func containsTransportFindsMoveCommandsAcrossNestedMacros() throws {
        var lib = MacroLibrary()
        let inner = macro("Inner", [.wait(seconds: 1), .transport(.next)])
        let outer = macro("Outer", [.runMacro(inner.id)])
        let clean = macro("Clean", [.selectLook(UUID())])
        try lib.save(inner); try lib.save(outer); try lib.save(clean)
        #expect(lib.firstTransport(in: outer.id) == .next)
        #expect(lib.firstTransport(in: clean.id) == nil)
        #expect(lib.firstTransport(in: UUID()) == nil)
    }

    @Test func firstTransportSurvivesACycleInDecodedData() {
        // A library decoded from damaged storage may contain a cycle; the search must still end.
        let a = UUID(), b = UUID()
        let lib = MacroLibrary(unvalidated: [macro("A", [.runMacro(b)], id: a), macro("B", [.runMacro(a)], id: b)])
        #expect(lib.firstTransport(in: a) == nil)
    }

    @Test func issuesReportsDamageInUnvalidatedData() {
        let a = UUID(), b = UUID()
        let lib = MacroLibrary(unvalidated: [macro("A", [.runMacro(b)], id: a), macro("B", [.runMacro(a)], id: b)])
        #expect(lib.issues().contains(.cycle(["A", "B", "A"])))
    }
}
