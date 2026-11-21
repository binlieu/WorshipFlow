// MEDIA-010 item 5: hot folders. The operator points the bin at a folder; its videos, pictures and sound appear as a
// source and stay in step with the folder. No file system and no watcher here: a fake lister and a fake watcher, and a
// fake clock for the play order. Nothing asserts on wall-clock time.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

/// A folder tree the test edits. Records every call so a test can prove nothing but listing ever happens to a file.
final class FakeFolders: FolderListing, @unchecked Sendable {
    private let lock = NSLock()
    private var folders: [String: [String: Int64]] = [:]
    private(set) var listCalls = 0

    func create(_ path: String, _ files: [String: Int64] = [:]) { lock.lock(); folders[path] = files; lock.unlock() }
    func put(_ path: String, _ name: String, size: Int64) { lock.lock(); folders[path]?[name] = size; lock.unlock() }
    func drop(_ path: String, _ name: String) { lock.lock(); folders[path]?[name] = nil; lock.unlock() }
    func vanish(_ path: String) { lock.lock(); folders[path] = nil; lock.unlock() }
    func snapshot(_ path: String) -> [String: Int64]? { lock.lock(); defer { lock.unlock() }; return folders[path] }

    func list(folder path: String) throws -> [FolderFile] {
        lock.lock(); defer { lock.unlock() }
        listCalls += 1
        guard let files = folders[path] else { throw FolderListingError.missing }
        return files.map { FolderFile(name: $0.key, size: $0.value) }
    }
}

@MainActor
final class FakeWatching: FolderWatching {
    private(set) var watched: [String] = []
    private var handlers: [String: @MainActor () -> Void] = [:]
    func watch(path: String, onChange: @escaping @MainActor () -> Void) -> any FolderWatch {
        watched.append(path)
        handlers[path] = onChange
        return Token { [weak self] in self?.handlers[path] = nil }
    }
    func fire(_ path: String) { handlers[path]?() }
    var activeCount: Int { handlers.count }
    final class Token: FolderWatch {
        let onCancel: () -> Void
        init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
        func cancel() { onCancel() }
    }
}

@MainActor
struct HotRig {
    let store: LibraryStore
    let fs: FakeFolders
    let watching: FakeWatching
    let model: HotFolderModel

    init(store: LibraryStore? = nil, files: FakeFolders? = nil) throws {
        let store = try store ?? LibraryStore.inMemory()
        let fs = files ?? FakeFolders()
        let watching = FakeWatching()
        self.store = store
        self.fs = fs
        self.watching = watching
        model = HotFolderModel(store: store, listing: fs, watching: watching, prober: FakeProber())
    }

    func settle(_ id: UUID? = nil) async { await model.rescan(id); await model.rescan(id) }
    func names(_ id: UUID) -> [String] { model.state(of: id)?.items.map(\.name) ?? [] }
}

@MainActor
@Suite struct MEDIA010_HotFolderTests {
    @Test func filesAddedAndRemovedAreReflectedAndOtherFilesAreIgnored() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a", ["one.mov": 100, "two.mp4": 100, "notes.txt": 5, ".DS_Store": 9, "pic.jpg": 50, "hymn.wav": 70])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.settle(folder.id)
        #expect(Set(r.names(folder.id)) == ["one", "two", "pic", "hymn"])
        let kinds = Dictionary(uniqueKeysWithValues: (r.model.state(of: folder.id)?.items ?? []).map { ($0.name, $0.kind) })
        #expect(kinds == ["one": .video, "two": .video, "pic": .image, "hymn": .audio])
        r.fs.put("/hot/a", "three.mov", size: 100)
        await r.settle(folder.id)
        #expect(r.names(folder.id).contains("three"))
        r.fs.drop("/hot/a", "one.mov")
        await r.model.rescan(folder.id)
        #expect(!r.names(folder.id).contains("one"), "a removed file goes at once")
    }

    @Test func aFileStillBeingCopiedIsHeldBackUntilItsSizeIsStable() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a", ["done.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.settle(folder.id)
        r.fs.put("/hot/a", "copying.mov", size: 10)
        await r.model.rescan(folder.id)
        #expect(!r.names(folder.id).contains("copying"))
        #expect(r.model.state(of: folder.id)?.heldBack == ["copying.mov"])
        r.fs.put("/hot/a", "copying.mov", size: 400)       // it grew: still not complete
        await r.model.rescan(folder.id)
        #expect(!r.names(folder.id).contains("copying") && r.model.pendingCount == 1)
        await r.model.rescan(folder.id)                    // same size twice in a row: complete
        #expect(r.names(folder.id).contains("copying") && r.model.pendingCount == 0)
    }

    @Test func anEmptyFileIsNeverReady() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a", ["empty.mov": 0])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.settle(folder.id)
        #expect(r.names(folder.id).isEmpty)
    }

    @Test func itemsAreInNameOrderTheWayAPersonReadsThem() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a", ["b.mov": 1, "A.mov": 1, "a10.mov": 1, "a2.mov": 1])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.settle(folder.id)
        #expect(r.names(folder.id) == ["A", "a2", "a10", "b"])
    }

    @Test func anItemKeepsItsIdAcrossScansAndRelaunchesAndDiffersBetweenFolders() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a", ["one.mov": 100]); r.fs.create("/hot/b", ["one.mov": 100])
        let a = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        let b = try #require(await r.model.add(path: "/hot/b", bookmark: nil))
        await r.settle()
        let first = try #require(r.model.state(of: a.id)?.items.first)
        await r.settle()
        #expect(r.model.state(of: a.id)?.items.first?.id == first.id)
        #expect(r.model.state(of: b.id)?.items.first?.id != first.id)
        let again = try HotRig(store: r.store, files: r.fs)
        await again.model.load()
        await again.settle()
        #expect(again.model.state(of: a.id)?.items.first?.id == first.id, "plays and cues that named it keep working")
    }

    @Test func probedLengthAndTheFilePathAreOnTheItem() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a", ["one.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.settle(folder.id)
        let item = try #require(r.model.state(of: folder.id)?.items.first)
        #expect(item.path == "/hot/a/one.mov" && item.duration == 10 && item.kind == .video)
    }

    @Test func severalFoldersAreAllowedAndSurviveARelaunchWithTheirBookmark() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a"); r.fs.create("/hot/b")
        let bookmark = Data([1, 2, 3])
        let a = try #require(await r.model.add(path: "/hot/a", bookmark: bookmark))
        _ = try #require(await r.model.add(path: "/hot/b", bookmark: nil))
        #expect(r.model.folders.count == 2)
        let again = try HotRig(store: r.store, files: r.fs)
        await again.model.load()
        #expect(again.model.folders.map(\.folder.path) == ["/hot/a", "/hot/b"])
        #expect(again.model.state(of: a.id)?.folder.bookmark == bookmark)
        #expect(again.watching.watched.sorted() == ["/hot/a", "/hot/b"], "a loaded folder is watched again")
    }

    @Test func addingTheSameFolderTwiceReturnsTheExistingOne() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a")
        let first = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        let second = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        #expect(first.id == second.id && r.model.folders.count == 1)
    }

    @Test func removingAFolderForgetsItAndNeverTouchesAFile() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a", ["one.mov": 100])
        let before = r.fs.snapshot("/hot/a")
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.settle(folder.id)
        await r.model.remove(folder.id)
        #expect(r.model.folders.isEmpty && r.watching.activeCount == 0)
        #expect(r.fs.snapshot("/hot/a") == before, "the files are as they were: nothing is moved, copied or deleted")
        let again = try HotRig(store: r.store, files: r.fs)
        await again.model.load()
        #expect(again.model.folders.isEmpty)
    }

    @Test func aFolderThatIsGoneShowsAsMissingWithoutThrowingAndCanBePointedAgain() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a", ["one.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.settle(folder.id)
        r.fs.vanish("/hot/a")
        await r.model.rescan(folder.id)
        #expect(r.model.state(of: folder.id)?.status == .missing)
        #expect(r.model.state(of: folder.id)?.items.isEmpty == true)
        #expect(r.model.lastError == nil, "a missing folder is shown, not raised at the operator")
        r.fs.create("/hot/moved", ["one.mov": 100])
        await r.model.relocate(folder.id, to: "/hot/moved", bookmark: nil)
        await r.settle(folder.id)
        let state = try #require(r.model.state(of: folder.id))
        #expect(state.status == .ok && state.folder.path == "/hot/moved" && state.items.map(\.name) == ["one"])
        #expect(state.folder.id == folder.id)
        #expect(r.watching.watched.last == "/hot/moved")
    }

    @Test func aFolderThatIsMissingAtLaunchDoesNotBlockLoadingOrTheShow() async throws {
        let store = try LibraryStore.inMemory()
        let r = try HotRig(store: store)
        r.fs.create("/hot/a")
        _ = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        let again = try HotRig(store: store)           // a fresh file system: the folder is not there
        await again.model.load()
        await again.settle()
        #expect(again.model.folders.first?.status == .missing)
        let workspace = WorkspaceModel(store: store, clock: ManualSaveClock())
        await workspace.load()
        let song = try #require(await workspace.importLyrics(title: "S", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 1))
        await workspace.openPresentation(song.id)
        await workspace.goLive()
        await workspace.next()
        #expect(workspace.show.liveIndex == 1 && workspace.lastError == nil)
    }

    @Test func theWatcherCallingBackRescansTheFolder() async throws {
        let r = try HotRig()
        r.fs.create("/hot/a", ["one.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.settle(folder.id)
        r.fs.put("/hot/a", "two.mov", size: 100)
        r.watching.fire("/hot/a")
        await r.model.waitForRescans()
        await r.model.rescan(folder.id)
        #expect(r.names(folder.id).contains("two"))
    }

    @Test func theModelReportsEachChangeOfItemsToTheBin() async throws {
        let r = try HotRig()
        var heard: [[UUID: [MediaAsset]]] = []
        r.model.onAssetsChange = { heard.append($0) }
        r.fs.create("/hot/a", ["one.mov": 100])
        let folder = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        await r.settle(folder.id)
        #expect(heard.last?[folder.id]?.map(\.name) == ["one"])
        let count = heard.count
        await r.model.rescan(folder.id)       // nothing changed: nothing is reported
        #expect(heard.count == count)
    }
}

@MainActor
@Suite struct MEDIA010_PlayFolderTests {
    private func rig() async throws -> (MediaRig, HotRig, HotFolder) {
        let media = try MediaRig()
        let hot = try HotRig(store: media.store)
        hot.fs.create("/hot/a", ["b.mov": 100, "a.mov": 100, "c.mov": 100, "z.png": 10, "s.wav": 10])
        let folder = try #require(await hot.model.add(path: "/hot/a", bookmark: nil))
        await hot.settle(folder.id)
        media.model.setHotAssets(folder.id, hot.model.state(of: folder.id)?.items ?? [])
        media.model.showStateChanged(isLive: true)
        return (media, hot, folder)
    }

    private func background(_ m: MediaRig) -> String? { m.model.layers.background.flatMap { m.model.asset($0.selection.assetID)?.name } }
    private func foreground(_ m: MediaRig) -> String? { m.model.layers.foreground.flatMap { m.model.asset($0.selection.assetID)?.name } }

    @Test func hotItemsCanBeFoundAndUsedLikeBinItemsButAreNotInTheBin() async throws {
        let (media, hot, folder) = try await rig()
        let item = try #require(hot.model.state(of: folder.id)?.items.first)
        #expect(media.model.asset(item.id) != nil && media.model.assets.isEmpty)
        media.model.setBackground(item.id)
        #expect(media.model.layers.background?.selection.assetID == item.id)
        #expect(try await media.store.mediaAssets(kind: nil).isEmpty, "nothing is added to the library's bin")
    }

    @Test func playFolderOnTheBackgroundPlaysVideosInNameOrderAndLoops() async throws {
        let (media, _, folder) = try await rig()
        media.model.playFolder(folder.id, on: .background)
        #expect(background(media) == "a" && media.model.playingFolderID == folder.id)
        media.clock.advance(10.5); media.model.tick()
        #expect(background(media) == "b")
        media.clock.advance(10.5); media.model.tick()
        #expect(background(media) == "c")
        media.clock.advance(10.5); media.model.tick()
        #expect(background(media) == "a", "after the last it starts again")
    }

    @Test func playFolderOnTheForegroundAdvancesWhenAClipEndsAndByThePlayersOwnReport() async throws {
        let (media, _, folder) = try await rig()
        media.model.playFolder(folder.id, on: .foreground)
        #expect(foreground(media) == "a")
        media.clock.advance(10.5); media.model.tick()
        #expect(foreground(media) == "b")
        media.clock.advance(9.5); _ = media.model.playerReportedEnd()
        #expect(foreground(media) == "c")
        media.clock.advance(9.5); _ = media.model.playerReportedEnd()
        #expect(foreground(media) == "a")
    }

    @Test func aFolderWithOneVideoRepeatsIt() async throws {
        let media = try MediaRig()
        let hot = try HotRig(store: media.store)
        hot.fs.create("/hot/one", ["only.mov": 10])
        let folder = try #require(await hot.model.add(path: "/hot/one", bookmark: nil))
        await hot.settle(folder.id)
        media.model.setHotAssets(folder.id, hot.model.state(of: folder.id)?.items ?? [])
        media.model.playFolder(folder.id, on: .background)
        media.clock.advance(10.5); media.model.tick()
        #expect(background(media) == "only")
    }

    @Test func aFilesAddedLaterJoinTheOrderAndARemovedOneLeavesIt() async throws {
        let (media, hot, folder) = try await rig()
        media.model.playFolder(folder.id, on: .background)
        hot.fs.put("/hot/a", "aa.mov", size: 100)
        hot.fs.drop("/hot/a", "b.mov")
        await hot.settle(folder.id)
        media.model.setHotAssets(folder.id, hot.model.state(of: folder.id)?.items ?? [])
        media.clock.advance(10.5); media.model.tick()
        #expect(background(media) == "aa", "next after a, in the order as it is now")
        media.clock.advance(10.5); media.model.tick()
        #expect(background(media) == "c")
    }

    @Test func aChoiceFromTheBinOrAClearEndsThePlayFolder() async throws {
        let (media, hot, folder) = try await rig()
        let item = try #require(hot.model.state(of: folder.id)?.items.last)
        media.model.playFolder(folder.id, on: .background)
        media.model.setBackground(item.id)
        #expect(media.model.playingFolderID == nil)
        media.clock.advance(10.5); media.model.tick()
        #expect(background(media) == item.name, "it is not replaced behind the operator's back")
        media.model.playFolder(folder.id, on: .background)
        media.model.clearBackground()
        #expect(media.model.playingFolderID == nil && media.model.layers.background == nil)
    }

    @Test func aFolderThatBecomesEmptyOrMissingEndsThePlayWithoutThrowing() async throws {
        let (media, hot, folder) = try await rig()
        media.model.playFolder(folder.id, on: .background)
        hot.fs.vanish("/hot/a")
        await hot.model.rescan(folder.id)
        media.model.setHotAssets(folder.id, hot.model.state(of: folder.id)?.items ?? [])
        media.clock.advance(10.5); media.model.tick()
        #expect(media.model.layers.background == nil && media.model.playingFolderID == nil)
    }

    @Test func playingAFolderWithNoVideosSaysSoAndChangesNothing() async throws {
        let media = try MediaRig()
        let hot = try HotRig(store: media.store)
        hot.fs.create("/hot/p", ["x.png": 10])
        let folder = try #require(await hot.model.add(path: "/hot/p", bookmark: nil))
        await hot.settle(folder.id)
        media.model.setHotAssets(folder.id, hot.model.state(of: folder.id)?.items ?? [])
        media.model.playFolder(folder.id, on: .background)
        #expect(media.model.layers.background == nil && media.model.lastError != nil)
    }

    @Test func aFolderOnTheForegroundNeedsALiveShowLikeAnyClip() async throws {
        let (media, _, folder) = try await rig()
        media.model.showStateChanged(isLive: false)
        media.model.playFolder(folder.id, on: .foreground)
        #expect(media.model.layers.foreground == nil && media.model.playingFolderID == nil)
    }
}
