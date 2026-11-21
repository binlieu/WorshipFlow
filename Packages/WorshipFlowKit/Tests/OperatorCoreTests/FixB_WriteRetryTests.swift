// FIX-B R12: settings and media writes are flushed with everything else, and a failed write is retried like a draft.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

/// Fails every write while `failing` is true.
private final class Outage: @unchecked Sendable {
    private let lock = NSLock()
    private var down = false
    private var calls = 0
    var failing: Bool {
        get { lock.lock(); defer { lock.unlock() }; return down }
        set { lock.lock(); down = newValue; lock.unlock() }
    }
    var attempts: Int { lock.lock(); defer { lock.unlock() }; return calls }
    struct Down: LocalizedError { var errorDescription: String? { "The disk is not writable." } }
    func check(_ key: String) throws {
        lock.lock(); calls += 1; let isDown = down; lock.unlock()
        if isDown { throw Down() }
    }
}

@MainActor
@Suite struct SettingsWriteRetryTests {
    private func loaded(_ outage: Outage, clock: ManualSaveClock) async throws -> (SettingsModel, LibraryStore) {
        let store = try LibraryStore.inMemory()
        let settings = SettingsModel(store: store, defaultProfiles: SettingsModelTests.defaults, clock: clock)
        await settings.load()
        await settings.flush()
        settings.writeInterceptor = { try outage.check($0) }
        return (settings, store)
    }

    @Test func aFailedSettingsWriteIsRetriedWithBackOffAndShownUntilItSucceeds() async throws {
        let outage = Outage(), clock = ManualSaveClock()
        let (settings, store) = try await loaded(outage, clock: clock)
        outage.failing = true
        let look = settings.addLook()
        await settings.flush()
        #expect(settings.writeProblem?.contains("disk is not writable") == true)
        #expect(settings.lastError != nil)
        #expect(try await store.looks().contains { $0.id == look.id } == false)
        let attemptsAfterFailure = outage.attempts
        outage.failing = false
        await clock.advance(by: 1)
        #expect(outage.attempts == attemptsAfterFailure)           // not before the back-off
        await clock.advance(by: 2)
        await settings.flush()
        #expect(try await store.looks().contains { $0.id == look.id })
        #expect(settings.writeProblem == nil)
    }

    @Test func flushWritesWhatEarlierFailed() async throws {
        let outage = Outage(), clock = ManualSaveClock()
        let (settings, store) = try await loaded(outage, clock: clock)
        outage.failing = true
        let look = settings.addLook()
        await settings.flush()
        #expect(try await store.looks().contains { $0.id == look.id } == false)
        outage.failing = false
        await settings.flush()                                      // quit or resign-active
        #expect(try await store.looks().contains { $0.id == look.id })
        #expect(settings.writeProblem == nil)
    }

    @Test func aNewerWriteIsNeverOverwrittenByAnOlderFailedOne() async throws {
        let outage = Outage(), clock = ManualSaveClock()
        let (settings, store) = try await loaded(outage, clock: clock)
        let id = try #require(settings.currentLook?.id)
        outage.failing = true
        settings.renameLook(id, to: "Old name")
        await settings.flush()
        outage.failing = false
        settings.renameLook(id, to: "New name")
        await settings.flush()
        await clock.advance(by: 120)
        await settings.flush()
        #expect(try await store.looks().first { $0.id == id }?.name == "New name")
        #expect(settings.writeProblem == nil)
    }

    @Test func aPropAddedWhileTheDiskFailedKeepsItsBookmarkWhenLaterChangesSupersedeIt() async throws {
        let outage = Outage(), clock = ManualSaveClock()
        let (settings, store) = try await loaded(outage, clock: clock)
        let prop = Prop(id: UUID(), name: "Cross", imagePath: "/x.png", frame: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1), opacity: 1, isOn: true)
        outage.failing = true
        settings.addProp(prop, bookmark: Data([1, 2, 3]))
        await settings.flush()
        settings.setProp(prop.id, isOn: false)                      // supersedes the failed add
        await settings.flush()
        outage.failing = false
        await settings.flush()
        #expect(try await store.props().first { $0.id == prop.id }?.isOn == false)
        #expect(await settings.bookmark(forProp: prop.id) == Data([1, 2, 3]))
    }
}

@MainActor
@Suite struct MediaWriteRetryTests {
    @Test func aFailedBackgroundWriteIsRetriedAndFlushedByTheModel() async throws {
        let outage = Outage(), clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let model = MediaModel(store: store, prober: FakeProber(), isAvailable: { _ in true }, clock: clock)
        await model.load()
        let asset = try #require(await model.add(url: URL(fileURLWithPath: "/media/loop.mov")))
        model.writeInterceptor = { try outage.check($0) }
        outage.failing = true
        model.setBackground(asset.id)
        await model.flush()
        #expect(model.writeProblem?.contains("disk is not writable") == true)
        #expect(try await store.state(for: MediaModel.backgroundKey) == nil)
        outage.failing = false
        await model.flush()
        #expect(try await store.state(for: MediaModel.backgroundKey) == asset.id.uuidString)
        #expect(model.writeProblem == nil)
    }
}
