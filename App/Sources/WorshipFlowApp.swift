// OUT-004: app entry point, menus and lifecycle.
import SwiftUI
import OperatorCore
import OutputEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // HWTEST-001: `--hardware-test --output <path>` runs the hardware test with no window and exits.
        if let launch = HardwareTestLaunchMode.launch, launch.isHeadless {
            NSApp.setActivationPolicy(.accessory)          // no Dock icon, no window, nothing takes focus
            Task.detached {
                let code = await HardwareTestHeadless.run(launch, environment: AppHardwareTest.environment(),
                                                          realProvider: AppHardwareTest.realProvider(),
                                                          log: { FileHandle.standardError.write(Data("[hardware-test] \($0)\n".utf8)) })
                exit(code)
            }
            return
        }
        OutputCoordinator.warmUp()         // compiles the shaders on a background task, before any screen opens
        MainActor.assumeIsolated {
            NSApp.activate()
            AppModel.shared.installSystemHooks()
            AppModel.shared.startWorkspace()
            AppModel.shared.startSoakIfRequested()
        }
    }

    /// R4: closing windows never ends the app while the screens are open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated { AppModel.shared.quitDecision(for: .lastWindowClosed) == .allow }
    }

    /// Typed text is written before the app goes away (NFR-07).
    func applicationDidResignActive(_ notification: Notification) {
        Task { @MainActor in await AppModel.shared.flushWorkspace() }
    }

    /// R4: Quit asks first while the screens are open. R12: everything is written before the app goes away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let proceed: Bool = MainActor.assumeIsolated {
            switch AppModel.shared.quitDecision(for: .quitCommand) {
            case .allow: return true
            case .refuse: return false
            case .confirm(let title, let message, let confirmTitle):
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = title
                alert.informativeText = message
                alert.addButton(withTitle: "Cancel")          // the default button is the safe one
                alert.addButton(withTitle: confirmTitle)
                return alert.runModal() == .alertSecondButtonReturn
            }
        }
        guard proceed else { return .terminateCancel }
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
                .modifier(HardwareTestLauncher())
        }
        .defaultSize(width: 1560, height: 900)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(HardwareTestLaunchMode.opensHardwareTest ? .suppressed : .automatic)
        .commands { WorkspaceCommands(app: AppModel.shared) }

        // HWTEST-001: the guided hardware test. `--hardware-test` opens it straight away instead of the workspace.
        Window("Hardware Test", id: "hardware-test") {
            HardwareTestView(controller: AppModel.shared.hardwareTest)
        }
        .defaultSize(width: 760, height: 860)
        .defaultLaunchBehavior(HardwareTestLaunchMode.opensHardwareTest && !HardwareTestLaunchMode.isHeadless ? .presented : .suppressed)
    }
}

/// Menus. Return, Space and the arrow keys are handled by a key monitor, not by menu key equivalents, because a
/// menu shortcut without a modifier would fire while a volunteer is typing in a text field.
struct WorkspaceCommands: Commands {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Presentation") { app.newPresentation() }.keyboardShortcut("n")
            Button("Import Lyrics…") { app.openImport(existing: nil) }.keyboardShortcut("i")
        }
        // R4: Command-H hides every window of the app, the screens included, so it is off while they are open.
        CommandGroup(replacing: .appVisibility) {
            Button("Hide WORSHIPFLOW") { NSApp.hide(nil) }.keyboardShortcut("h").disabled(!app.mayHide)
            Button("Hide Others") { NSApp.hideOtherApplications(nil) }.keyboardShortcut("h", modifiers: [.command, .option])
            Button("Show All") { NSApp.unhideAllApplications(nil) }
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
        CommandGroup(after: .help) {
            Divider()
            Button("Hardware Test…") { openWindow(id: "hardware-test") }
        }
        CommandGroup(after: .textEditing) {
            Button("Find Songs") { app.ui.focusSearch += 1 }.keyboardShortcut("f")
        }
        CommandMenu("Show") {
            Button("Go Live (Return)") { app.goLive() }
            Button("Next (Right arrow or Space)") { app.next() }
            Button("Previous (Left arrow)") { app.previous() }
            Button("Clear (Escape)") { app.clear() }
            Button("Clear All (Shift-Escape)") { app.clearAll() }
            Button("Stop") { app.stopShow() }
            Divider()
            Button("Quick Edit Live Slide…") { app.ui.showQuickEdit = true }.keyboardShortcut("e")
        }
    }
}

/// HWTEST-001: with `--hardware-test` the first window that appears is swapped for the Hardware Test window. (The scene
/// launch-behaviour modifiers above are the intended route; this makes the flag work even where they are not honoured.)
struct HardwareTestLauncher: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        content.task {
            guard HardwareTestLaunchMode.opensHardwareTest, !HardwareTestLaunchMode.isHeadless else { return }
            openWindow(id: "hardware-test")
            dismissWindow(id: "workspace")
        }
    }
}
