// FIX-Q (OUT): what reaches each output for a recorded command sequence did not change. A fixed sequence of show commands is replayed through
// the same gate the app uses (`LivePublicationGate`) and the same snapshot (`PublishedScenes`), for an audience window, a stage window and a
// broadcast screen that is keyed (Fill and Key); every scene that would be published is serialised with sorted keys and folded into one SHA-256
// digest, in order. The digest was recorded on the code as it stood before FIX-Q's changes (which touch views and observation, not composition).
// If it ever differs, composition or the order or the number of publications changed.
import Testing
import Foundation
import CryptoKit
import Domain
@testable import OperatorCore

@Suite struct FIXQ_PublishedScenesDigestTests {
    static let audienceID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let stageID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    static let broadcastID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!

    static var profiles: [ScreenProfile] {
        [ScreenProfile(id: audienceID, name: "Audience", role: .audience, destination: .window),
         ScreenProfile(id: stageID, name: "Stage", role: .stage, destination: .window),
         ScreenProfile(id: broadcastID, name: "Broadcast", role: .broadcast,
                       destination: .sdi(deviceID: "test-card", connector: 1, keying: true, fillAlphaMode: .premultiplied))]
    }

    static func deck(_ id: UUID, _ count: Int) -> ShowDeck {
        ShowDeck(presentationID: id, slides: (0..<count).map { n in
            SlideContent(primary: "Line \(n) of the song\nsecond line \(n)", secondary: n % 2 == 0 ? "Translated \(n)" : nil)
        })
    }

    /// The recorded sequence: loads, selections, Go Live, Next and Previous past both ends, Clear, Blackout, Clear background, a quick edit, Stop.
    static let commands: [ShowCommand] = {
        let a = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!, b = UUID(uuidString: "00000000-0000-0000-0000-00000000D002")!
        var out: [ShowCommand] = [.load(deck(a, 7)), .select(index: 3), .trigger(index: 3)]
        out += Array(repeating: .next, count: 5)
        out += Array(repeating: .previous, count: 9)
        out += [.select(index: 5), .blackout, .next, .clear, .next, .liftHolds, .clearBackground, .previous, .restoreBackground]
        out += [.quickEdit(index: 2, content: SlideContent(primary: "Corrected words", secondary: "Corrigé")), .restore(deck: deck(a, 7), selectedIndex: 2)]
        out += [.load(deck(b, 4)), .trigger(index: 0), .next, .next, .next, .next, .clearAll, .blackout, .blackout, .stop]
        out += [.trigger(index: 1), .stop, .next, .previous]
        return out
    }()

    /// Returns the digest and the number of publications.
    static func replay() throws -> (digest: String, publications: Int) {
        var state = ShowState()
        var gate = LivePublicationGate()
        var hasher = SHA256()
        var publications = 0
        let profiles = Self.profiles
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for command in commands {
            state.apply(command)
            guard gate.shouldPublish(LiveOutputKey(state: state, notes: nil)) else { continue }
            publications += 1
            let snapshot = PublishedScenes(state: state, clockText: "10:30", profiles: profiles)
            for profile in profiles {
                hasher.update(data: Data(profile.role.rawValue.utf8))
                hasher.update(data: try encoder.encode(snapshot.scene(forScreen: profile.id)))
            }
        }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), publications)
    }

    @Test func theScenesPublishedForTheRecordedSequenceAreTheOnesRecordedBeforeFIXQ() throws {
        let result = try Self.replay()
        print("FIXQ digest \(result.digest) publications \(result.publications)")
        #expect(result.publications == Self.recordedPublications)
        #expect(result.digest == Self.recordedDigest)
    }

    @Test func theSequenceReachesAudienceStageAndTheKeyedBroadcastScreenAndMoreThanOnce() throws {
        let result = try Self.replay()
        #expect(result.publications > 20)
        let keyed = Self.profiles.first { $0.role == .broadcast }
        #expect(keyed?.destination.isKeyed == true)
    }

    static let recordedPublications = 29
    static let recordedDigest = "8dee754a42757fa6e5202fe494efe9d54085bdc53402167838a1ed5c664264f3"
}
