// FIX-Y item 11 (SC-21; REVIEW-4 L1): the Identify screens labels are taken down when the operator opens the screens and when the screen list changes.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct FIXY_IdentifyDismissTests {
    private let profiles = UI007f_ScreenLookTests.profiles()

    @Test func openingTheScreensDismissesTheLabels() {
        #expect(ScreenIdentify.shouldDismiss(screensOpen: true, before: profiles, after: profiles))
    }

    @Test func aChangeOfTheScreenListDismissesTheLabels() {
        var renamed = profiles
        renamed[1].name = "Foyer"
        #expect(ScreenIdentify.shouldDismiss(screensOpen: false, before: profiles, after: renamed))
        #expect(ScreenIdentify.shouldDismiss(screensOpen: false, before: profiles, after: Array(profiles.dropLast())))
    }

    @Test func nothingChangingLeavesThemUntilTheirOwnTimeEnds() {
        #expect(!ScreenIdentify.shouldDismiss(screensOpen: false, before: profiles, after: profiles))
    }

    @Test func theAppTakesThemDownWhenTheScreensOpenAndWhenTheListChanges() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        func source(_ name: String) throws -> String { try String(contentsOf: url.appendingPathComponent("App/Sources/\(name)"), encoding: .utf8) }
        let model = try source("AppModel.swift")
        let open = try #require(model.range(of: "private func openScreensNow()"))
        #expect(String(model[open.lowerBound...].prefix(400)).contains("ScreensIdentifier.shared.dismiss()"), "opening the screens leaves the labels up")
        let map = try source("ScreensMap.swift")
        #expect(map.contains("ScreenIdentify.shouldDismiss") && map.contains(".onChange(of: app.profiles)"), "a changed screen list leaves the labels up")
    }
}
