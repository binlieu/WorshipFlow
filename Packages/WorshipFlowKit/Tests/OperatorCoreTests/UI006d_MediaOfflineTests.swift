// UI-006d: files the bin lists that cannot be read now (the design's "1 file is offline" callout and Locate...). The decisions are pure
// (the words, the plan of which other files move with the chosen one); the model keeps the set, finds a file again and keeps the asset's
// identity so slides that use it as their background recover without being touched. No wall clock, no real files.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct UI006d_OfflineWordsTests {
    private func asset(_ path: String) -> MediaAsset {
        MediaAsset(name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, kind: .video, path: path)
    }

    @Test func anUnmountedDiskIsNamedAsTheReason() {
        let a = asset("/Volumes/Backup/Baptism testimony.mov")
        let s = MediaOffline.summary(offline: [a], directoryExists: { _ in false })
        #expect(s?.headline == "1 file is offline")
        #expect(s?.detail == "Baptism testimony.mov \u{2014} the disk \"Backup\" is not connected.")
    }

    @Test func aMountedDiskWithoutTheFileSaysItWasMoved() {
        let a = asset("/Volumes/Backup/a.mov")
        let s = MediaOffline.summary(offline: [a], directoryExists: { $0 == "/Volumes/Backup" })
        #expect(s?.detail == "a.mov \u{2014} the file is not there any more (moved, renamed or deleted).")
    }

    @Test func aPathOffTheVolumesFolderIsJustNotFound() {
        let s = MediaOffline.summary(offline: [asset("/Users/x/a.mov")], directoryExists: { _ in true })
        #expect(s?.detail?.contains("not there any more") == true)
    }

    @Test func severalFilesListTwoNamesAndCountTheRest() {
        let all = ["a", "b", "c", "d"].map { asset("/Volumes/D/\($0).mov") }
        let s = MediaOffline.summary(offline: all, directoryExists: { _ in false })
        #expect(s?.headline == "4 files are offline")
        #expect(s?.detail == "a.mov, b.mov and 2 more.")
    }

    @Test func nothingOfflineSaysNothing() {
        #expect(MediaOffline.summary(offline: [], directoryExists: { _ in true }) == nil)
    }
}

@Suite struct UI006d_RelocationPlanTests {
    private func asset(_ path: String) -> MediaAsset { MediaAsset(name: "x", kind: .video, path: path) }

    @Test func theChosenFileMovesTheTargetAndItsNeighboursThatAreInTheNewFolder() {
        let a = asset("/Volumes/Old/Loops/a.mov"), b = asset("/Volumes/Old/Loops/b.mov"), c = asset("/Volumes/Old/Loops/c.mov")
        let d = asset("/Volumes/Other/d.mov")
        let present: Set<String> = ["/Volumes/New/Loops/a.mov", "/Volumes/New/Loops/b.mov"]
        let plan = MediaOffline.relocationPlan(target: a, chosen: "/Volumes/New/Loops/a.mov", offline: [a, b, c, d], fileExists: { present.contains($0) })
        #expect(plan == [.init(assetID: a.id, newPath: "/Volumes/New/Loops/a.mov"), .init(assetID: b.id, newPath: "/Volumes/New/Loops/b.mov")])
    }

    @Test func aTargetWithADifferentNameStillMovesAloneWhenChosen() {
        let a = asset("/Volumes/Old/a.mov")
        let plan = MediaOffline.relocationPlan(target: a, chosen: "/Users/x/renamed.mov", offline: [a], fileExists: { _ in true })
        #expect(plan == [.init(assetID: a.id, newPath: "/Users/x/renamed.mov")])
    }
}

@MainActor
@Suite struct UI006d_OfflineModelTests {
    @Test func theModelKnowsWhichFilesCannotBeReadAndTellsWhenTheyComeBack() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov"), b = await rig.add("b.mov")
        rig.files.lose(a.path)
        await rig.model.refreshOffline()
        #expect(rig.model.offlineIDs == [a.id])
        rig.files.lose(b.path); rig.files.restore(a.path)
        await rig.model.refreshOffline()
        #expect(rig.model.offlineIDs == [b.id])
    }

    @Test func addingOrRemovingRechecksWithoutTheCallerAsking() async throws {
        let rig = try MediaRig()
        rig.files.lose("/media/gone.mov")
        let gone = await rig.add("gone.mov")
        await rig.model.finishOfflineCheck()
        #expect(rig.model.offlineIDs == [gone.id])
        await rig.model.remove(gone.id)
        await rig.model.finishOfflineCheck()
        #expect(rig.model.offlineIDs.isEmpty)
    }

    @Test func locatingKeepsTheIdentityAndStoresTheNewPath() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov")
        rig.files.lose(a.path)
        await rig.model.refreshOffline()
        let outcome = await rig.model.locate([.init(assetID: a.id, newPath: "/new/a.mov")], bookmarks: [:])
        #expect(outcome.moved == [a.id] && outcome.problems.isEmpty)
        let now = try #require(rig.model.asset(a.id))
        #expect(now.path == "/new/a.mov" && now.id == a.id && now.name == a.name)
        await rig.model.finishOfflineCheck()
        #expect(rig.model.offlineIDs.isEmpty)
        let stored = try await rig.store.mediaAssets(kind: nil)
        #expect(stored.map(\.path) == ["/new/a.mov"], "persisted")
    }

    @Test func aFileOfAnotherKindIsRefusedAndNothingChanges() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov")
        let outcome = await rig.model.locate([.init(assetID: a.id, newPath: "/new/a.png")], bookmarks: [:])
        #expect(outcome.moved.isEmpty && outcome.problems.count == 1)
        #expect(rig.model.asset(a.id)?.path == a.path)
        #expect(rig.model.lastError != nil)
    }

    @Test func aFileThatCannotBeReadIsRefused() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov")
        let outcome = await rig.model.locate([.init(assetID: a.id, newPath: "/new/bad.mov")], bookmarks: [:])
        #expect(outcome.moved.isEmpty && rig.model.asset(a.id)?.path == a.path)
    }

    @Test func aPathAnotherBinItemAlreadyUsesIsRefused() async throws {
        let rig = try MediaRig()
        let a = await rig.add("a.mov"), b = await rig.add("b.mov")
        let outcome = await rig.model.locate([.init(assetID: a.id, newPath: b.path)], bookmarks: [:])
        #expect(outcome.moved.isEmpty && outcome.problems.count == 1)
        #expect(rig.model.asset(a.id)?.path == a.path)
    }
}
