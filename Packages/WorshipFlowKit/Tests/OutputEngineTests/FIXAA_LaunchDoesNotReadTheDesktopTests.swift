// FIX-AA: the app builds the Hardware Test controller at launch (SwiftUI evaluates the window's content), and the controller listed the
// Desktop there. macOS asks for permission to read the Desktop, and the main thread waited inside `open` until the operator answered:
// the app looked frozen at launch. The app's controller must not read the folder until the Hardware Test window asks.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

@MainActor
@Suite struct FIXAA_LaunchDoesNotReadTheDesktopTests {
    private func controller(parent: URL, looksAtOnce: Bool) -> HardwareTestController {
        let driver = HardwareDriverStatus(isInstalled: false, message: "Blackmagic Desktop Video is not installed.")
        let real = HardwareTestProvider(isSimulated: false, devices: { [] }, driver: { driver })
        return HardwareTestController(realProvider: { real }, environment: .fixed, screensOpen: { false },
                                      workingFolder: parent.appendingPathComponent("work"), unfinishedParent: parent, looksAtOnce: looksAtOnce)
    }

    @Test func aControllerToldNotToLookLeavesTheFolderAloneUntilRefresh() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixaa-\(UUID().uuidString)", isDirectory: true)
        let left = parent.appendingPathComponent("2027-01-15-0800-WorshipFlow-hardware-test-unfinished", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        #expect(controller(parent: parent, looksAtOnce: true).unfinishedRun != nil, "the default still finds the folder at once")
        let c = controller(parent: parent, looksAtOnce: false)
        #expect(c.unfinishedRun == nil, "nothing was read at init")
        c.refresh()
        #expect(c.unfinishedRun != nil, "the window's own refresh finds it")
    }

    @Test func theAppBuildsItsControllerWithoutLookingAndTheWindowRescansWhenItAppears() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: root.appendingPathComponent("App/Sources/AppModel.swift"), encoding: .utf8)
        #expect(model.contains("looksAtOnce: false"))
        let view = try String(contentsOf: root.appendingPathComponent("App/Sources/HardwareTestView.swift"), encoding: .utf8)
        #expect(view.contains(".task { await controller.rescan() }"))
    }
}
