// FIX-J item 9 (UI-005h): the digests of the unchanged user themes and the Classic looks, compared only on the machine they were recorded on.
// The structural checks of the same guarantee (byte-for-byte storage, decoded equality, defaults) are in `UI005h_MigrationV13Tests` and always run.
import Testing
import Foundation
import Domain
@testable import RenderEngine

@Suite struct FIXJ_GoldenDigestTests {
    init() { #expect(UI005hFixtures.registerInter()) }

    @Test func theIdentityIsHashedAndCarriesNothingPersonal() {
        let id = MachineIdentity.current
        #expect(id == MachineIdentity.hash(MachineIdentity.description))
        #expect(id.count >= 12 && id.allSatisfy { $0.isHexDigit })
        for personal in [NSUserName(), ProcessInfo.processInfo.hostName, NSFullUserName(), NSHomeDirectory()] where personal.count > 2 {
            #expect(!MachineIdentity.description.contains(personal), "the identity text must not carry a personal string")
        }
        #expect(MachineIdentity.hash("a") != MachineIdentity.hash("b"))
    }

    @Test func saysWhyTheDigestsAreSkippedOnAnotherMachine() {
        if !MachineIdentity.matchesRecording { print("FIXJ golden digests skipped: \(MachineIdentity.skipReason)") }
        #expect(MachineIdentity.skipReason.contains(MachineIdentity.recording) && MachineIdentity.skipReason.contains(MachineIdentity.current))
    }

    @Test(.enabled(if: MachineIdentity.matchesRecording, "golden digests were recorded on a different machine (macOS or GPU): see the printed reason"))
    func theUserThemesDrawTheDigestsRecordedBeforeUI005h() throws {
        let c = try Compositor()
        for theme in UI005hFixtures.userThemes {
            let digest = UI005hFixtures.digest(try UI005hFixtures.frames(of: theme, compositor: c)[0])
            #expect(digest == UI005h_Golden.userThemeAudience[theme.name], "\(theme.name)")
        }
    }

    @Test(.enabled(if: MachineIdentity.matchesRecording, "golden digests were recorded on a different machine (macOS or GPU): see the printed reason"))
    func theClassicLooksDrawTheirEarlierDigests() throws {
        let c = try Compositor()
        let audience = try UI005hFixtures.frames(of: .classicFullScreen, compositor: c)[0]
        let broadcast = try UI005hFixtures.frames(of: .classicLowerThird, compositor: c)[1]
        #expect(UI005hFixtures.digest(audience) == UI005h_Golden.oldFullScreenAudience)
        #expect(UI005hFixtures.digest(broadcast) == UI005h_Golden.oldLowerThirdBroadcast)
    }
}
