// FIX-AB: what the views are wired to, from the source (a scroll and a click cannot be driven from a unit test; the running-app numbers are in
// AI/reports/FIX-AB-report.md).
import Testing
import Foundation

@Suite struct FIXAB_ViewSourceTests {
    private func root() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
    private func source(_ name: String) throws -> String { try String(contentsOf: root().appendingPathComponent("App/Sources/\(name)"), encoding: .utf8) }

    @Test func theGridAndTheListFollowLiveAndPreviewThroughTheOnePureRule() throws {
        let text = try source("CentrePane.swift")
        let follow = try #require(text.range(of: "private struct ScrollToSelection: View"))
        let body = String(text[follow.lowerBound...].prefix(1500))
        #expect(body.contains("liveIndex(app, workspace)") && body.contains("workspace.showParts.selectedIndex") && body.contains("ShowGridFollow.target("))
        #expect(body.contains("proxy.scrollTo(run)") && body.contains("proxy.scrollTo(key)"), "a cell of a section that was never on screen needs its section made first")
        #expect(!body.contains("anchor:"), "no anchor: the smallest scroll that shows the cell, so a visible cell does not jump")
        #expect(!body.contains("Timer") && !body.contains("asyncAfter") && !body.contains("Task.sleep"), "no polling or retry loop")
        #expect(text.components(separatedBy: "ScrollToSelection(app: app").count - 1 == 2, "the grid and the list both use it")
        #expect(try source("ScriptureView.swift").contains("ShowGridFollow.target("), "a Scripture passage's grid follows Live as well")
    }

    @Test func aBinClickAsBackgroundGoesThroughTheHeardPath() throws {
        let app = try source("AppModel.swift")
        let start = try #require(app.range(of: "func performDockAction(_ action: MediaDockAction) {"))
        #expect(String(app[start.lowerBound...].prefix(400)).contains("case .setBackground(let id): media?.setBackgroundFromBin(id)"))
        #expect(try source("MediaDockView.swift").contains("media.setBackgroundFromBin(asset.id)"))
        #expect(!(try source("MediaDockView.swift").contains("media.setBackground(asset.id)")))
        let panel = try source("MediaBinPanel.swift")
        #expect(!panel.contains("media.setBackground(asset.id)") && panel.components(separatedBy: "media.setBackgroundFromBin(asset.id)").count - 1 == 2)
    }
}
