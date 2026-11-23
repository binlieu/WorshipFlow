// UI-007f (OUT): a per-screen Look changes what an output shows, so for a library that uses none the scenes must not move by a byte. The FIX-Q
// sequence is replayed with a global Look that has its own theme, layers and props per role, for an audience window, a stage window and a keyed
// broadcast screen (Fill and Key, composed in all three channels by the scene itself), and every scene is folded into one SHA-256 digest. The
// digest below was recorded on the code as it stood before UI-007f changed anything (HEAD 0f89ce3, `look:` only) and must not change.
import Testing
import Foundation
import CryptoKit
import Domain
@testable import OperatorCore

@Suite struct UI007f_ScenesDigestTests {
    static let profiles = FIXQ_PublishedScenesDigestTests.profiles
    static let audienceID = FIXQ_PublishedScenesDigestTests.audienceID
    static let stageID = FIXQ_PublishedScenesDigestTests.stageID
    static let broadcastID = FIXQ_PublishedScenesDigestTests.broadcastID

    static let globalLook = Look(id: UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!, name: "Global", screens: [
        audienceID: ScreenLook(themeID: Theme.lowerThirdID, visibleLayers: [.background, .slide, .props]),
        stageID: ScreenLook(themeID: nil, visibleLayers: [.slide, .props]),
        broadcastID: ScreenLook(themeID: Theme.lowerThirdID, visibleLayers: [.slide]),
    ])

    static let props: [Prop] = [
        Prop(id: UUID(uuidString: "00000000-0000-0000-0000-00000000F0A1")!, name: "Strap", imagePath: "", frame: NormalizedRect(x: 0.1, y: 0.8, width: 0.4, height: 0.1),
             targets: [.audience, .broadcast, .stage], kind: .text, text: TextPropSpec(text: "Sunday service", fontSize: 40, anchor: .bottomLeft)),
        Prop(id: UUID(uuidString: "00000000-0000-0000-0000-00000000F0A2")!, name: "Logo", imagePath: "/pictures/logo.png", frame: NormalizedRect(x: 0.8, y: 0.05, width: 0.1, height: 0.1)),
    ]

    static func replay(overrides: Bool = false) throws -> (digest: String, publications: Int) {
        var state = ShowState()
        var gate = LivePublicationGate()
        var hasher = SHA256()
        var publications = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for command in FIXQ_PublishedScenesDigestTests.commands {
            state.apply(command)
            guard gate.shouldPublish(LiveOutputKey(state: state, notes: nil)) else { continue }
            publications += 1
            let snapshot = makeSnapshot(state: state, overrides: overrides)
            for profile in profiles {
                hasher.update(data: Data(profile.role.rawValue.utf8))
                hasher.update(data: try encoder.encode(snapshot.scene(forScreen: profile.id)))
            }
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), publications)
    }

    static func makeSnapshot(state: ShowState, overrides: Bool) -> PublishedScenes {
        overrides
            ? PublishedScenes(state: state, clockText: "10:30", profiles: profiles, look: globalLook, props: props,
                              screenLooks: ScreenLooks.overrides(profiles: profiles, global: globalLook, looks: [globalLook]))
            : PublishedScenes(state: state, clockText: "10:30", profiles: profiles, look: globalLook, props: props)
    }

    @Test func scenesUnderAGlobalLookAreTheOnesRecordedBeforeUI007f() throws {
        let result = try Self.replay()
        print("UI007f digest \(result.digest) publications \(result.publications)")
        #expect(result.publications == Self.recordedPublications)
        #expect(result.digest == Self.recordedDigest)
    }

    static let recordedPublications = 29
    static let recordedDigest = "86933eae500b060f55c9df10fd0973d0b910626eb42f08e1bb46ade30e77a028"
}
