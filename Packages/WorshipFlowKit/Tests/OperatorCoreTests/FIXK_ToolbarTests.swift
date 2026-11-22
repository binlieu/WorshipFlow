// FIX-K items 2, 5 and 6 (owner, 2026-11-21): the toolbar has no red LIVE chip in Edit, Stage or Screens ("it looks too busy"), the mode switcher sits at the
// left directly after the title block, and the transport bar's Clear has no menu ("no need anymore since we have all clear icons") while every command it
// held stays reachable from its icon, its key and the app's menu bar.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct FIXK_ToolbarTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func source(_ path: String) throws -> String { try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8) }

    // MARK: Toolbar contents per mode

    @Test func noModeHasALiveChipInTheToolbar() {
        for mode in WorkspaceMode.allCases {
            #expect(!ToolbarLayout.items(for: mode).contains(.liveChip), "\(mode)")
        }
        // Keyboard transport is a key matter: the three modes without a transport bar still have the keys (the router does not look at the mode).
        for mode in [WorkspaceMode.edit, .stage, .screens] { #expect(!mode.showsTransportBar) }
    }

    @Test func theSwitcherIsDirectlyAfterTheTitleBlockInEveryModeAndTheRestKeepsItsOrder() {
        let expected: [ToolbarItem] = [.windowButtons, .sidebarToggle, .titleBlock, .modeSwitcher, .timers, .pills]
        for mode in WorkspaceMode.allCases { #expect(ToolbarLayout.items(for: mode) == expected, "\(mode)") }
        #expect(ToolbarLayout.switcherIsLeading)
    }

    @Test func theToolbarSourceDrawsNoChipAndNoSpacerBeforeTheSwitcher() throws {
        let text = try source("App/Sources/ContentView.swift")
        #expect(!text.contains("liveChip"), "the live chip is gone from the toolbar")
        let toolbar = try #require(text.components(separatedBy: "private var operatorToolbar").last?.components(separatedBy: "private var screensButton").first)
        let title = try #require(toolbar.range(of: "titleBlock"))
        let switcher = try #require(toolbar.range(of: "modeSwitcher"))
        let between = String(toolbar[title.upperBound..<switcher.lowerBound])
        #expect(!between.contains("Spacer"), "nothing pushes the switcher away from the title block")
    }

    // MARK: The Clear menu is gone, its commands are not

    @Test func theTransportBarsClearIsAPlainButtonWithoutAMenuOrChevron() throws {
        let text = try source("App/Sources/TransportBar.swift")
        let clear = try #require(text.components(separatedBy: "private var clearControl").last?.components(separatedBy: "@ViewBuilder private var stateBadge").first)
        #expect(!clear.contains("Menu {") && !clear.contains("chevron") && !clear.contains("ClearControl.layerMenu"))
        #expect(clear.contains("app.clear()") && clear.contains("\"Clear\""))
        #expect(!text.contains("showClearMenuPreview") && !text.contains("clearMenuPreview"))
    }

    @Test func everyCommandTheMenuHeldIsStillReachableFromAnIconAKeyAndTheMenuBar() throws {
        let app = try source("App/Sources/WorshipFlowApp.swift")
        let titles: [ClearControl.Action: String] = [.clearWords: "Clear (Escape)", .clearAll: "Clear All (Shift-Escape)", .clearBackground: "Clear Background",
                                                       .clearForeground: "Clear Foreground", .clearMusic: "Clear Music"]
        let icons: [ClearControl.Action: ClearIcon] = [.clearWords: .lyric, .clearAll: .all, .clearBackground: .background, .clearForeground: .foreground, .clearMusic: .music]
        for action in [ClearControl.Action.clearWords, .clearAll, .clearBackground, .clearForeground, .clearMusic] {
            #expect(!action.shortcut.isEmpty, "\(action.title) has a key")
            #expect(app.contains("Button(\"\(try #require(titles[action]))\")"), "\(action.title) is in the menu bar")
            let icon = try #require(icons[action])
            #expect(ClearIconState.state(for: icon, live: ClearLiveState(hasLiveWords: true, backgroundKind: .video, foregroundKind: .video, musicName: "x")).tooltip.hasSuffix(action.shortcut),
                    "\(action.title) has an icon whose tooltip names its key")
        }
    }
}
