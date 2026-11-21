// OUT-002: sleep prevention counting logic with an injected backend.
import Testing
import Foundation
@testable import OutputEngine

// @unchecked Sendable: test double, only touched from the main actor.
final class FakePowerBackend: PowerAssertionBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID: UInt32 = 100
    private(set) var live: Set<UInt32> = []
    private(set) var createCount = 0
    var refuse = false

    func create(_ kind: PowerAssertionKind, reason: String) -> UInt32? {
        lock.lock(); defer { lock.unlock() }
        createCount += 1
        if refuse { return nil }
        nextID += 1
        live.insert(nextID)
        return nextID
    }

    func release(_ id: UInt32) { lock.lock(); live.remove(id); lock.unlock() }
}

@MainActor
@Suite struct SleepGuardTests {
    @Test func holdsDisplayAndSystemAssertionsWhileAnythingRuns() {
        let backend = FakePowerBackend()
        let g = SleepGuard(backend: backend)
        #expect(g.isHolding == false)
        g.update(runningCount: 1)
        #expect(g.isHolding && backend.live.count == 2)
        g.update(runningCount: 4)
        g.update(runningCount: 2)
        #expect(backend.live.count == 2 && backend.createCount == 2)   // idempotent: no extra assertions
        g.update(runningCount: 0)
        #expect(g.isHolding == false && backend.live.isEmpty)
    }

    @Test func canBeHeldAgainAfterRelease() {
        let backend = FakePowerBackend()
        let g = SleepGuard(backend: backend)
        g.update(runningCount: 1); g.update(runningCount: 0); g.update(runningCount: 1)
        #expect(backend.live.count == 2 && backend.createCount == 4)
    }

    @Test func refusedAssertionIsReportedAndRetried() {
        let backend = FakePowerBackend()
        backend.refuse = true
        let g = SleepGuard(backend: backend)
        g.update(runningCount: 1)
        #expect(g.isHolding == false && g.failedKinds.count == 2)
        backend.refuse = false
        g.update(runningCount: 1)
        #expect(g.isHolding && g.failedKinds.isEmpty)
    }

    @Test func zeroWhenNothingHeldIsHarmless() {
        let backend = FakePowerBackend()
        let g = SleepGuard(backend: backend)
        g.update(runningCount: 0)
        #expect(backend.createCount == 0)
    }
}
