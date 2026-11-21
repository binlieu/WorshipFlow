// OUT-004: app entry point, menus and lifecycle.
import SwiftUI
import OperatorCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.activate()
            AppModel.shared.installSystemHooks()
            AppModel.shared.startWorkspace()
            AppModel.shared.startSoakIfRequested()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Typed text is written before the app goes away (NFR-07).
    func applicationDidResignActive(_ notification: Notification) {
        Task { @MainActor in await AppModel.shared.flushWorkspace() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await AppModel.shared.flushWorkspace()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.shutdown() }
    }
}

@main
struct WorshipFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("WORSHIPFLOW", id: "workspace") {
            ContentView(app: AppModel.shared)
        }
        .defaultSize(width: 1560, height: 900)
        .windowResizability(.contentMinSize)
        .commands { WorkspaceCommands(app: AppModel.shared) }
    }
}

/// Menus. Return, Space and the arrow keys are handled by a key monitor, not by menu key equivalents, because a
/// menu shortcut without a modifier would fire while a volunteer is typing in a text field.
struct WorkspaceCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Presentation") { app.newPresentation() }.keyboardShortcut("n")
            Button("Import Lyrics…") { app.openImport(existing: nil) }.keyboardShortcut("i")
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { app.undoEdit() }.keyboardShortcut("z")
            Button("Redo") { app.redoEdit() }.keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandMenu("Insert") {
            Button("Text Box") { app.insertObject(.textBox) }
            Button("Rectangle") { app.insertObject(.rectangle) }
            Button("Ellipse") { app.insertObject(.ellipse) }
            Button("Rounded Rectangle") { app.insertObject(.roundedRectangle) }
            Button("Image…") { app.insertImage() }
            Divider()
            Button("Duplicate Object") { app.duplicateObject() }.keyboardShortcut("d")
        }
        CommandGroup(after: .textEditing) {
            Button("Find Songs") { app.ui.focusSearch += 1 }.keyboardShortcut("f")
        }
        CommandMenu("Show") {
            Button("Go Live (Return)") { app.goLive() }
            Button("Next (Right arrow or Space)") { app.next() }
            Button("Previous (Left arrow)") { app.previous() }
            Button("Clear (Escape)") { app.clear() }
            Button("Stop") { app.stopShow() }
            Divider()
            Button("Quick Edit Live Slide…") { app.ui.showQuickEdit = true }.keyboardShortcut("e")
        }
    }
}
