// FIX-F item 7 (LIB-004c): Import cannot be started twice, and a file over 64 MB is refused before it is read. Written before the
// fix; invented text only. Model level; the button's disabled state is `canStartImport`.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct FIXF_ImportGuardTests {
    private func write(_ file: TranslationFile) throws -> URL {
        let url = L4C.temp("translation.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.encoded().write(to: url)
        return url
    }

    @Test func aSecondImportWhileOneIsRunningIsIgnored() async throws {
        let r = try await L4C.rig(install: [])
        let first = try write(L4C.english())
        let second = try write(L4C.vietnamese())
        #expect(r.scripture.canStartImport)
        let running = Task { await r.scripture.importTranslation(from: first) }
        while true { if case .running = r.scripture.importState { break }; await Task.yield() }
        #expect(r.scripture.canStartImport == false, "the button is disabled while an import runs")
        await r.scripture.importTranslation(from: second)       // ignored
        await running.value
        #expect(r.scripture.translations.map(\.code) == ["en-test"], "only the first file was imported")
        guard case .finished = r.scripture.importState else { Issue.record("\(r.scripture.importState)"); return }
        #expect(r.scripture.canStartImport)
    }

    @Test func anImportWhileTheReplaceQuestionIsWaitingIsIgnored() async throws {
        let r = try await L4C.rig(install: [L4C.english()])
        var changed = L4C.english(name: "Renamed text")
        changed.setVerse("Another line, invented.", book: BookID("JHN"), chapter: 3, verse: 1)
        await r.scripture.importTranslation(from: try write(changed))
        #expect(r.scripture.importState == .needsReplace(code: "en-test", name: "Renamed text"))
        #expect(r.scripture.canStartImport == false)
        await r.scripture.importTranslation(from: try write(L4C.vietnamese()))     // ignored: the question is still open
        #expect(r.scripture.importState == .needsReplace(code: "en-test", name: "Renamed text"))
        #expect(r.scripture.translations.map(\.code) == ["en-test"])
        await r.scripture.confirmReplace()
        #expect(r.scripture.translations.first?.name == "Renamed text", "the answer is for the file that asked")
        #expect(r.scripture.canStartImport)
    }

    @Test func aFileOver64MegabytesIsRefusedBeforeItIsRead() async throws {
        let r = try await L4C.rig(install: [])
        let url = L4C.temp("huge.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(64 * 1024 * 1024 + 1))          // sparse: nothing is written
        try handle.close()
        await r.scripture.importTranslation(from: url)
        guard case .failed(let message) = r.scripture.importState else { Issue.record("\(r.scripture.importState)"); return }
        #expect(message.contains("64 MB") && message.contains("huge.json"), Comment(rawValue: message))
        #expect(!message.contains("is not a WorshipFlow translation file"), "refused for its size, not read as a bad file")
        #expect(r.scripture.translations.isEmpty)
        #expect(r.scripture.canStartImport)
    }

    @Test func aFileOfExactly64MegabytesIsStillRead() async throws {
        let r = try await L4C.rig(install: [])
        let url = L4C.temp("edge.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(64 * 1024 * 1024))
        try handle.close()
        await r.scripture.importTranslation(from: url)
        guard case .failed(let message) = r.scripture.importState else { Issue.record("\(r.scripture.importState)"); return }
        #expect(message.contains("is not a WorshipFlow translation file"), "it was read (and is not a translation file)")
    }
}
