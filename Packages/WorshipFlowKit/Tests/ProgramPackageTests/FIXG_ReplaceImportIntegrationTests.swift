// FIX-G items 3 and 14 (LIB-005): the real importer inside the real workspace's import wrapper, with a presentation open and typing
// that was still waiting to be saved. "Use the imported one" replaces the stored content, the backup holds what was typed, and
// nothing typed earlier comes back over the import.
import Testing
import Foundation
import Domain
import OperatorCore
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

/// A clock that never fires by itself: waiting drafts are written only when the code asks for it (flush).
private struct IdleClock: SaveClock {
    @MainActor var now: TimeInterval { 0 }
    @MainActor func sleep(for seconds: TimeInterval) async throws { try await Task.sleep(for: .seconds(100_000)) }
}

@MainActor
@Suite struct FIXG_ReplaceImportIntegrationTests {
    @Test func useImportedWithAnOpenPresentationAndWaitingTyping() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        try await makeConflicting(church, home: home)

        let workspace = WorkspaceModel(store: church, clock: IdleClock())
        await workspace.load()
        await workspace.openPresentation(home.songOne)
        #expect(workspace.slides[0].content.primary == "First line of verse (church edit)")
        workspace.editSlide(id: workspace.slides[0].id, content: SlideContent(primary: "typed and not yet saved"))
        let dates = FixedDates()

        var result: ProgramImportResult?
        _ = try await workspace.importingProgram {
            let r = try await ProgramImporter.apply(contents, into: church, choice: .useImported,
                                                    hooks: ProgramImportHooks(now: { dates.tick() }))
            result = r
            return ProgramImportOutcome(playlistID: r.playlistID, replaced: r.replacedPresentationIDs)
        }
        let done = try #require(result)
        #expect(done.replacedPresentationIDs.contains(home.songOne))

        // The open presentation shows the imported words, and so does the library, also after anything waiting is written.
        #expect(workspace.slides[0].content.primary == "First line of verse")
        await workspace.flush()
        #expect(try await church.slides(of: home.songOne).first?.content.primary == "First line of verse")
        #expect(workspace.slides[0].content.primary == "First line of verse")

        // The way back: the backup was written after the typing was saved, so it holds the typing.
        let backup = try #require(done.backupURL)
        let old = try LibraryStore.open(at: backup)
        #expect(try await old.slides(of: home.songOne).first?.content.primary == "typed and not yet saved")
        try old.close()
    }
}
