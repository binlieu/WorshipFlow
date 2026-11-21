// HW-003: the pure parts of the input side: signal state, timestamp units, and protocol conformance.
// Verification level: Unit Tested. Capture itself has never run.
import Foundation
import SDIEngine
import Testing
@testable import DeckLinkSDI

private func requireDevice<D: SDIDevice>(_: D.Type) {}

@Suite struct HW003_InputMappingTests {
    @Test func theRealTypesConformToTheEngineProtocols() {
        let _: any SDIInputPort.Type = DeckLinkInputPort.self
        let _: any SDIOutputPort.Type = DeckLinkOutputPort.self
        requireDevice(DeckLinkDevice.self)
        let _: DeckLinkDevice.InputPort.Type = DeckLinkInputPort.self
        let _: DeckLinkDevice.Port.Type = DeckLinkOutputPort.self
    }

    @Test func aSignalIsLockedOnlyWhileRunningWithFramesAndAKnownMode() {
        let mode = SDIVideoMode.hd1080p5994
        #expect(DeckLinkInputPort.signal(hasSignal: true, mode: mode, running: true) == .locked(mode))
        #expect(DeckLinkInputPort.signal(hasSignal: false, mode: mode, running: true) == .noSignal)
        #expect(DeckLinkInputPort.signal(hasSignal: true, mode: nil, running: true) == .noSignal)
        #expect(DeckLinkInputPort.signal(hasSignal: true, mode: mode, running: false) == .noSignal)
    }

    @Test func timestampsAreConvertedFromNanosecondsToTheModesTimeScale() {
        // One frame of 1080p59.94 is 1001/60000 s = 16_683_333 ns, which is 1001 units of 1/60000 s.
        #expect(DeckLinkInputPort.timestamp(nanoseconds: 1_000_000_000, timeScale: 60000) == 60000)
        #expect(DeckLinkInputPort.timestamp(nanoseconds: 0, timeScale: 60000) == 0)
        #expect(DeckLinkInputPort.timestamp(nanoseconds: 16_683_333, timeScale: 60000) == 1000)
        #expect(DeckLinkInputPort.timestamp(nanoseconds: 2_500_000_000, timeScale: 30000) == 75000)
    }

    @Test func aLongRunningClockDoesNotOverflow() {
        let tenDays: Int64 = 10 * 24 * 3600 * 1_000_000_000
        #expect(DeckLinkInputPort.timestamp(nanoseconds: tenDays, timeScale: 60000) == Int64(10 * 24 * 3600 * 60000))
    }

    @Test func impossibleTimestampsAreNil() {
        #expect(DeckLinkInputPort.timestamp(nanoseconds: -1, timeScale: 60000) == nil)
        #expect(DeckLinkInputPort.timestamp(nanoseconds: 1_000_000_000, timeScale: 0) == nil)
        #expect(DeckLinkInputPort.timestamp(nanoseconds: Int64.max, timeScale: Int64.max) == nil)
    }
}
