// UI-004: what the About window says. The developer's name and address are the only person details in it, and no path.
import Testing
import Foundation
@testable import Domain

@Suite struct UI004_AboutInfoTests {
    @Test func theDeveloperAndTheProjectAreNamed() {
        #expect(AboutInfo.developerLine == "Developed by Simon Lieu")
        #expect(AboutInfo.developerEmail == "me@simonlieu.com")
        #expect(AboutInfo.developerMailURL.absoluteString == "mailto:me@simonlieu.com")
        #expect(AboutInfo.projectURL.absoluteString == "https://github.com/binlieu/WorshipFlow")
        #expect(AboutInfo.licenceLine.contains("Apache License 2.0"))
        #expect(AboutInfo.summary.contains("WorshipFlow"))
    }

    @Test func thirdPartyNoticesMatchTheNoticeFile() {
        let text = AboutInfo.thirdPartyNotices.joined(separator: "\n")
        #expect(text.contains("Blackmagic"))
        #expect(text.contains("GRDB.swift"))
        #expect(text.contains("MIT"))
    }

    @Test func nothingElsePersonalOrLocalAppears() {
        let all = ([AboutInfo.summary, AboutInfo.developerLine, AboutInfo.developerEmail, AboutInfo.licenceLine, AboutInfo.projectURL.absoluteString]
                   + AboutInfo.thirdPartyNotices).joined(separator: "\n")
        #expect(!all.contains("/Users"))
        #expect(!all.contains("/Volumes"))
        #expect(!all.contains("~/"))
        #expect(all.filter { $0 == "@" }.count == 1)
    }
}
