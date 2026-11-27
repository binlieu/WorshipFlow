// FIX-Y item 9 (OUT, SC-51; REVIEW-5 L15): the Look panel no longer says a Look applies to every screen; Show says which screens keep a Look of their
// own; deleting a Look asks first and names what changes (FIX-V's style: Cancel is the default, no system red).
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct FIXY_LookNoticesTests {
    private let sermon = UI007f_ScreenLookTests.sermon
    private let worship = UI007f_ScreenLookTests.worship

    @Test func thePanelTextNoLongerSaysEveryScreenAtOnce() {
        #expect(!LookNotices.panelText.contains("every screen at once"))
        #expect(LookNotices.panelText.contains("Look of its own") && LookNotices.panelText.contains("keeps"))
    }

    @Test func showSaysWhichScreensKeepTheirOwnLook() throws {
        let profiles = UI007f_ScreenLookTests.profiles(lobbyLook: sermon.id)
        let note = try #require(LookNotices.ownLookNotice(profiles: profiles, global: worship, looks: [worship, sermon]))
        #expect(note.contains("Lobby") && note.contains("Sermon") && !note.contains("Sanctuary"))
    }

    @Test func noScreenWithItsOwnLookMeansNoNotice() {
        #expect(LookNotices.ownLookNotice(profiles: UI007f_ScreenLookTests.profiles(), global: worship, looks: [worship, sermon]) == nil)
        // a screen whose choice is the show's Look anyway follows it
        #expect(LookNotices.ownLookNotice(profiles: UI007f_ScreenLookTests.profiles(lobbyLook: worship.id), global: worship, looks: [worship, sermon]) == nil)
    }

    @Test func aLongListIsShortenedAndCounted() throws {
        let many = (0..<6).map { ScreenProfile(id: UUID(), name: "Room \($0)", role: .audience, destination: .window, screenLookID: sermon.id) }
        let note = try #require(LookNotices.ownLookNotice(profiles: many, global: worship, looks: [worship, sermon]))
        #expect(note.contains("Room 0") && note.contains("+4 more") && !note.contains("Room 5"))
    }

    @Test func deletingALookAsksAndNamesTheScreensThatGoBackToTheShowsLook() {
        let profiles = UI007f_ScreenLookTests.profiles(lobbyLook: sermon.id)
        let p = LookNotices.deletePrompt(look: sermon, isShowLook: false, profiles: profiles)
        #expect(p.title.contains("Sermon"))
        #expect(p.message.contains("Lobby") && p.message.contains("show's Look") && p.message.contains("cannot be undone"))
        #expect(p.confirmTitle == "Delete Look")
    }

    @Test func deletingTheShowsLookSaysTheShowSwitches() {
        let p = LookNotices.deletePrompt(look: worship, isShowLook: true, profiles: UI007f_ScreenLookTests.profiles())
        #expect(p.message.contains("show") && p.message.contains("another Look"))
        #expect(!p.message.contains("chose it"))
    }

    @Test func theViewsUseThemAndNoDeleteLookIsOneClick() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        func source(_ name: String) throws -> String { try String(contentsOf: url.appendingPathComponent("App/Sources/\(name)"), encoding: .utf8) }
        let panel = try source("ControlPanels.swift")
        let start = try #require(panel.range(of: "struct LookPanel: View"))
        let lookPanel = String(panel[start.lowerBound...].prefix(2_600))
        #expect(lookPanel.contains("LookNotices.panelText") && lookPanel.contains("LookNotices.deletePrompt"))
        #expect(!lookPanel.contains("if let id = model.selectedLookID { model.deleteLook(id) }"), "Delete must ask first")
        #expect(!lookPanel.contains("role: .destructive"))
        #expect(try source("ShowInspector.swift").contains("LookNotices.ownLookNotice"))
    }
}
