// SYS-015 (OUT): migration v15 and its new stored fields change nothing that reaches an output for a library that uses none of them. The FIX-Q
// sequence is replayed again with slides that carry text, shape and image objects (the objects a v14 library can hold), and the scenes for an
// audience window, a stage window and a keyed broadcast screen are folded into one digest. The digest below was recorded on the code as it stood
// before SYS-015 touched anything (HEAD d7628c1), and must not change.
import Testing
import Foundation
import CryptoKit
import Domain
@testable import OperatorCore

@Suite struct SYS015_ScenesDigestTests {
    static func objects(_ n: Int) -> [SlideObject] {
        let id = { (k: Int) in UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000E%02d%02d", n, k))! }
        return [
            SlideObject(id: id(1), frame: NormalizedRect(x: 0.05, y: 0.05, width: 0.4, height: 0.2), opacity: 0.8,
                        content: .shape(ShapeObject(shape: .roundedRectangle(cornerRadius: 0.2), fill: ColorRGBA(red: 0.1, green: 0.2, blue: 0.3), strokeColor: .white, strokeWidth: 3))),
            SlideObject(id: id(2), frame: NormalizedRect(x: 0.5, y: 0.1, width: 0.4, height: 0.2),
                        content: .text(TextObject(text: "Caption \(n)", style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white), alignment: .leading, verticalAlignment: .top))),
            SlideObject(id: id(3), frame: NormalizedRect(x: 0.6, y: 0.6, width: 0.3, height: 0.3),
                        content: .image(ImageObject(path: "/pictures/logo-\(n).png", contentMode: .fill))),
        ]
    }

    static func deck(_ id: UUID, _ count: Int) -> ShowDeck {
        ShowDeck(presentationID: id, slides: (0..<count).map { n in
            SlideContent(primary: "Line \(n) of the song\nsecond line \(n)", secondary: n % 2 == 0 ? "Translated \(n)" : nil,
                         objects: n % 3 == 1 ? [] : objects(n))
        })
    }

    static let commands: [ShowCommand] = {
        let a = UUID(uuidString: "00000000-0000-0000-0000-00000000D011")!
        var out: [ShowCommand] = [.load(deck(a, 6)), .select(index: 0), .trigger(index: 0)]
        out += Array(repeating: .next, count: 6)
        out += Array(repeating: .previous, count: 3)
        out += [.blackout, .next, .liftHolds, .clear, .next, .clearBackground, .restoreBackground]
        out += [.quickEdit(index: 2, content: SlideContent(primary: "Corrected", objects: objects(9))), .stop]
        return out
    }()

    static func replay() throws -> (digest: String, publications: Int) {
        var state = ShowState()
        var gate = LivePublicationGate()
        var hasher = SHA256()
        var publications = 0
        let profiles = FIXQ_PublishedScenesDigestTests.profiles
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

    @Test func scenesWithObjectsForEveryOutputAreTheOnesRecordedBeforeSYS015() throws {
        let result = try Self.replay()
        print("SYS015 digest \(result.digest) publications \(result.publications)")
        #expect(result.publications == Self.recordedPublications)
        #expect(result.digest == Self.recordedDigest)
    }

    @Test func theSequenceDrawsItsObjectsOnTheAudienceScreen() throws {
        var state = ShowState()
        state.apply(.load(Self.deck(UUID(), 3)))
        state.apply(.trigger(index: 0))
        let snapshot = PublishedScenes(state: state, clockText: nil, profiles: FIXQ_PublishedScenesDigestTests.profiles)
        #expect(snapshot.scene(forScreen: FIXQ_PublishedScenesDigestTests.audienceID).objectLayers.count == 3)
    }

    static let recordedPublications = 18
    static let recordedDigest = "ab7dcfe9b230be15281e8a79bd3e5b9f5324df4ac19a04a4edb2e1860d649412"
}
