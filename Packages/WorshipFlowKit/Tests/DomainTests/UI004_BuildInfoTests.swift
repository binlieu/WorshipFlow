// UI-004: the version line the owner reads out and a tester's report carries. It is built from the app's Info.plist; a build made
// without git has no commit, and says so instead of inventing one.
import Testing
import Foundation
@testable import Domain

@Suite struct UI004_BuildInfoTests {
    private func info(version: String? = "0.0.1", build: String? = "41", commit: String? = "71d344d", date: String? = "2026-11-21") -> [String: Any] {
        var d: [String: Any] = [:]
        if let version { d["CFBundleShortVersionString"] = version }
        if let build { d["CFBundleVersion"] = build }
        if let commit { d["WFBuildCommit"] = commit }
        if let date { d["WFBuildDate"] = date }
        return d
    }

    @Test func theLineNamesVersionBuildCommitAndDate() {
        let b = BuildInfo(infoDictionary: info())
        #expect(b.line == "WorshipFlow 0.0.1 (build 41), commit 71d344d, built 2026-11-21")
        #expect(b.detail == "commit 71d344d, built 2026-11-21")
        #expect(!b.isDevelopmentBuild)
    }

    @Test func withoutACommitItIsADevelopmentBuild() {
        let b = BuildInfo(infoDictionary: info(commit: nil, date: nil))
        #expect(b.line == "WorshipFlow 0.0.1 (build 41), development build")
        #expect(b.detail == "development build")
        #expect(b.isDevelopmentBuild)
    }

    @Test func aDateAloneDoesNotMakeItAReleaseBuild() {
        #expect(BuildInfo(infoDictionary: info(commit: nil)).isDevelopmentBuild)
    }

    @Test func aCommitWithoutADateStillShowsTheCommit() {
        #expect(BuildInfo(infoDictionary: info(date: nil)).line == "WorshipFlow 0.0.1 (build 41), commit 71d344d")
    }

    @Test func aBuildWithUncommittedChangesSaysSo() {
        #expect(BuildInfo(infoDictionary: info(commit: "71d344d-dirty")).line.contains("commit 71d344d-dirty"))
    }

    @Test func junkInTheCommitOrDateIsIgnoredNotShown() {
        for junk in ["", "   ", "unknown", "$(WF_COMMIT)", "71d344d; rm -rf", "/Users/someone/repo"] {
            let b = BuildInfo(infoDictionary: info(commit: junk))
            #expect(b.isDevelopmentBuild, "commit \(junk)")
            #expect(!b.line.contains(junk) || junk.isEmpty || junk == "   ")
        }
        #expect(BuildInfo(infoDictionary: info(date: "yesterday")).detail == "commit 71d344d")
    }

    @Test func missingVersionAndBuildReadAsUnknown() {
        #expect(BuildInfo(infoDictionary: info(version: nil, build: nil, commit: nil, date: nil)).line == "WorshipFlow unknown (build unknown), development build")
        #expect(BuildInfo(infoDictionary: nil).line == "WorshipFlow unknown (build unknown), development build")
    }

    @Test func aBuildSettingThatWasNeverExpandedIsNotAVersion() {
        #expect(BuildInfo(infoDictionary: info(version: "$(MARKETING_VERSION)", build: "$(CURRENT_PROJECT_VERSION)")).line
                == "WorshipFlow unknown (build unknown), commit 71d344d, built 2026-11-21")
    }
}
