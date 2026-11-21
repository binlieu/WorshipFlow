// UI-004: the About window is not the show. Space, Return and the arrows pressed in it must not move the live slide.
import Testing
@testable import OperatorCore

@Suite struct UI004_AboutKeyGateTests {
    @Test func transportKeysAreOffInTheAboutWindow() {
        #expect(KeyRouting.isAboutWindow(title: "About WorshipFlow", identifier: nil))
        #expect(KeyRouting.isAboutWindow(title: nil, identifier: "about-AppWindow-2"))
        #expect(KeyRouting.isAboutWindow(title: "WorshipFlow", identifier: "workspace-AppWindow-1") == false)
        #expect(KeyRouting.transportKeysActive(windowTitle: "About WorshipFlow", windowIdentifier: "about-AppWindow-2", launchedWithHardwareTest: false) == false)
        #expect(KeyRouting.transportKeysActive(windowTitle: "WorshipFlow", windowIdentifier: "workspace-AppWindow-1", launchedWithHardwareTest: false))
    }
}
