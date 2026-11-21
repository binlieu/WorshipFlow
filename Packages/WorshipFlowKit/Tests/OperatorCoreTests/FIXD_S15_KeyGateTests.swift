// FIX-D S15: the transport keys do not drive the show while the Hardware Test window is the one in front, or when the app was
// started for a hardware test.
import Testing
import Foundation
@testable import OperatorCore

@Suite struct FIXD_S15_KeyGateTests {
    @Test func theHardwareTestWindowIsRecognisedByTitleOrIdentifier() {
        #expect(KeyRouting.isHardwareTestWindow(title: "Hardware Test", identifier: nil))
        #expect(KeyRouting.isHardwareTestWindow(title: " hardware test ", identifier: nil))
        #expect(KeyRouting.isHardwareTestWindow(title: nil, identifier: "hardware-test-AppWindow-1"))
        #expect(KeyRouting.isHardwareTestWindow(title: "WORSHIPFLOW", identifier: "workspace-AppWindow-1") == false)
        #expect(KeyRouting.isHardwareTestWindow(title: nil, identifier: nil) == false)
    }

    @Test func theKeysAreActiveInTheWorkspaceAndOffInTheHardwareTestWindow() {
        #expect(KeyRouting.transportKeysActive(windowTitle: "WORSHIPFLOW", windowIdentifier: "workspace-AppWindow-1", launchedWithHardwareTest: false))
        #expect(KeyRouting.transportKeysActive(windowTitle: "Hardware Test", windowIdentifier: "hardware-test-AppWindow-2", launchedWithHardwareTest: false) == false)
    }

    @Test func aSessionStartedForAHardwareTestHasNoTransportKeysAnywhere() {
        #expect(KeyRouting.transportKeysActive(windowTitle: "WORSHIPFLOW", windowIdentifier: "workspace-AppWindow-1", launchedWithHardwareTest: true) == false)
        #expect(KeyRouting.transportKeysActive(windowTitle: nil, windowIdentifier: nil, launchedWithHardwareTest: true) == false)
    }

    @Test func spaceReturnArrowsAndBWouldHaveDrivenTheShowWithoutTheGate() {
        // the routing itself is unchanged: it is the gate in front of it that keeps these keys away from the hidden show
        for key in [KeyboardKey.space, .returnKey, .rightArrow, .leftArrow, .b] {
            #expect(KeyRouting.decision(for: key, textInputFocused: false, sheetOpen: false) != .passThrough)
        }
    }
}
