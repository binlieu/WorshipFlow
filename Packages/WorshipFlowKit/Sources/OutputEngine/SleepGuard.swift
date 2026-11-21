// OUT-002: keeps the Mac awake while any output is running.
import Foundation
import IOKit.pwr_mgt

public enum PowerAssertionKind: Sendable, Equatable, CaseIterable {
    case preventDisplaySleep
    case preventSystemSleep
}

/// The system call behind `SleepGuard`, injectable so the counting logic can be tested.
public protocol PowerAssertionBackend: Sendable {
    /// Returns an opaque id, or nil if the assertion could not be created.
    func create(_ kind: PowerAssertionKind, reason: String) -> UInt32?
    func release(_ id: UInt32)
}

public struct IOKitPowerAssertionBackend: PowerAssertionBackend {
    public init() {}

    public func create(_ kind: PowerAssertionKind, reason: String) -> UInt32? {
        let type: String
        switch kind {
        case .preventDisplaySleep: type = kIOPMAssertionTypePreventUserIdleDisplaySleep
        case .preventSystemSleep: type = kIOPMAssertionTypePreventUserIdleSystemSleep
        }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason as CFString, &id)
        return result == kIOReturnSuccess ? id : nil
    }

    public func release(_ id: UInt32) { IOPMAssertionRelease(IOPMAssertionID(id)) }
}

/// Holds display and idle-system sleep assertions while at least one output runs.
@MainActor
public final class SleepGuard {
    private let backend: any PowerAssertionBackend
    private let reason: String
    private var held: [PowerAssertionKind: UInt32] = [:]
    /// Kinds the system refused the last time; shown to the operator by the app if non-empty.
    public private(set) var failedKinds: [PowerAssertionKind] = []

    public init(backend: any PowerAssertionBackend = IOKitPowerAssertionBackend(),
                reason: String = "WorshipFlow is presenting") {
        self.backend = backend
        self.reason = reason
    }

    public var isHolding: Bool { !held.isEmpty }

    /// Call whenever the number of running outputs may have changed. Idempotent.
    public func update(runningCount: Int) {
        if runningCount > 0 {
            failedKinds = []
            for kind in PowerAssertionKind.allCases where held[kind] == nil {
                if let id = backend.create(kind, reason: reason) { held[kind] = id } else { failedKinds.append(kind) }
            }
        } else {
            for (_, id) in held { backend.release(id) }
            held.removeAll()
            failedKinds = []
        }
    }
}
