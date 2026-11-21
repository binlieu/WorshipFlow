// OUT-001: app entry point.
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.activate()
            AppModel.shared.installSystemHooks()
            AppModel.shared.startSoakIfRequested()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }
}

@main
struct WorshipFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("WORSHIPFLOW") {
            ContentView(model: AppModel.shared)
        }
        .windowResizability(.contentMinSize)
    }
}
