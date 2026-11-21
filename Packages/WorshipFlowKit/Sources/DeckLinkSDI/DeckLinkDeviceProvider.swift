// HW-003 / SCRN-11: finds DeckLink cards, groups their sub-devices into cards, and follows hot-plug.
//
// Status: Implemented, Not Verified. On a Mac without the Blackmagic Desktop Video driver (the only situation it has run
// in) it returns no devices and reports the driver as absent.
import DeckLinkC
import Foundation
import SDIEngine
import Synchronization

public enum DeckLinkDeviceEvent: Sendable {
    case arrived(DeckLinkDevice)
    /// The last sub-device of the card went away.
    case removed(DeckLinkDevice)
    /// A card gained or lost a sub-device while still present (for example after a profile change by another program).
    case changed(DeckLinkDevice)
}

public final class DeckLinkDeviceProvider: Sendable {
    private struct State {
        var cards: [DeckLinkIdentifier: DeckLinkDevice] = [:]
        var discovery: DLBDiscovery?
        var onEvent: (@Sendable (DeckLinkDeviceEvent) -> Void)?
    }

    private let state = Mutex(State())

    public init() {}

    /// Driver presence, version and the operator message. Never throws.
    public var environment: DeckLinkEnvironment { DeckLinkEnvironment.current }

    /// Scans now and returns the cards in a stable order (by identifier text). Empty without the driver.
    public func devices() -> [DeckLinkDevice] {
        refresh()
        return state.withLock { $0.cards.values.sorted { $0.identifier.description < $1.identifier.description } }
    }

    /// Re-scans with IDeckLinkIterator and reconciles with what is already known. Cards keep their identity: the same
    /// `DeckLinkDevice` object is returned for a card that is still there.
    public func refresh() {
        let found = DLBBridge.enumerateDevices()
        reconcile(found: found)
    }

    /// Starts hot-plug notifications (IDeckLinkDiscovery). Throws `driverNotInstalled` when the driver is absent.
    /// `onEvent` runs on an SDK thread and must not block. Calling this again replaces the handler.
    public func startMonitoring(onEvent: @escaping @Sendable (DeckLinkDeviceEvent) -> Void) throws {
        state.withLock { $0.onEvent = onEvent }
        if state.withLock({ $0.discovery }) != nil { return }
        let discovery = DLBDiscovery(
            arrived: { [weak self] device in self?.arrived(device) },
            removed: { [weak self] device in self?.removed(device) })
        do {
            try discovery.start()
        } catch {
            state.withLock { $0.onEvent = nil }
            let nsError = error as NSError
            if nsError.domain == DLBErrorDomain, nsError.code == DLBError.Code.driverNotInstalled.rawValue { throw DeckLinkError.driverNotInstalled }
            throw error
        }
        state.withLock { $0.discovery = discovery }
    }

    public func stopMonitoring() {
        let discovery = state.withLock { s -> DLBDiscovery? in
            let d = s.discovery
            s.discovery = nil
            s.onEvent = nil
            return d
        }
        discovery?.stop()
    }

    /// The driver, every card and every open port, as plain values for the diagnostics screen and the test bundle.
    public func statusSnapshot() -> DeckLinkSnapshotValue {
        let env = environment
        return .object([
            "driverPresent": .bool(env.driverPresent),
            "apiVersion": env.apiVersion.map { .string($0) } ?? .null,
            "compiledAPIVersion": .string(env.compiledAPIVersion),
            "message": .string(env.message),
            "devices": .array(devices().map { $0.statusSnapshot() }),
        ])
    }

    // MARK: Reconciling

    private static func memberKey(_ info: DLBDeviceInfo) -> String {
        info.hasPersistentID ? "id:\(info.persistentID)" : "name:\(info.displayName)#\(info.subDeviceIndex)"
    }

    private static func cardIdentifier(_ info: DLBDeviceInfo) -> DeckLinkIdentifier {
        if info.hasDeviceGroupID, info.deviceGroupID != 0 { return .group(info.deviceGroupID) }
        if info.hasPersistentID { return .device(info.persistentID) }
        return .named(info.displayName)
    }

    private func arrived(_ device: DLBDevice) {
        let event = state.withLock { s -> DeckLinkDeviceEvent? in
            let info = device.info
            let id = Self.cardIdentifier(info)
            let key = Self.memberKey(info)
            if let card = s.cards[id] {
                if card.currentMembers().contains(where: { Self.memberKey($0.info) == key }) { return nil }
                card.addMember(device)
                return .changed(card)
            }
            let card = DeckLinkDevice(identifier: id, members: [device])
            s.cards[id] = card
            return .arrived(card)
        }
        emit(event)
    }

    private func removed(_ device: DLBDevice) {
        let key = Self.memberKey(device.info)
        let outcome = state.withLock { Self.remove(key: key, from: &$0) }
        outcome.gone.forEach { $0.markRemoved() }   // outside the lock: open ports report their failure from here
        emit(outcome.event)
    }

    private func reconcile(found: [DLBDevice]) {
        let foundKeys = Set(found.map { Self.memberKey($0.info) })
        var events: [DeckLinkDeviceEvent] = []
        // Departures first, so a card that went away and came back is reported as removed then arrived.
        let known = state.withLock { s in s.cards.values.flatMap { $0.currentMembers() } }
        for member in known where !foundKeys.contains(Self.memberKey(member.info)) {
            let key = Self.memberKey(member.info)
            let outcome = state.withLock { Self.remove(key: key, from: &$0) }
            outcome.gone.forEach { $0.markRemoved() }
            if let event = outcome.event { events.append(event) }
        }
        for device in found {
            let key = Self.memberKey(device.info)
            let id = Self.cardIdentifier(device.info)
            let event = state.withLock { s -> DeckLinkDeviceEvent? in
                if let card = s.cards[id] {
                    if card.currentMembers().contains(where: { Self.memberKey($0.info) == key }) { return nil }
                    card.addMember(device)
                    return .changed(card)
                }
                let card = DeckLinkDevice(identifier: id, members: [device])
                s.cards[id] = card
                return .arrived(card)
            }
            if let event { events.append(event) }
        }
        // Keep known cards' attributes current (a profile may have changed in another program).
        for card in state.withLock({ Array($0.cards.values) }) { card.refreshAll() }
        events.forEach(emit)
    }

    /// Removes one member by key from whichever card holds it. The caller tells the removed members they are gone.
    private static func remove(key: String, from s: inout State) -> (event: DeckLinkDeviceEvent?, gone: [DLBDevice]) {
        for (id, card) in s.cards {
            let outcome = card.removeMembers { memberKey($0.info) == key }
            guard !outcome.removed.isEmpty else { continue }
            if outcome.remaining == 0 {
                s.cards[id] = nil
                return (.removed(card), outcome.removed)
            }
            return (.changed(card), outcome.removed)
        }
        return (nil, [])
    }

    private func emit(_ event: DeckLinkDeviceEvent?) {
        guard let event else { return }
        let handler = state.withLock { $0.onEvent }
        handler?(event)
    }
}
