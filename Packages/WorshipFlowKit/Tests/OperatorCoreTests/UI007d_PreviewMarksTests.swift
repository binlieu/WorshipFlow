// UI-007d (MEDIA): the bin player (a preview on this Mac only) honours a clip's mark in and mark out: it starts at the in mark, and the player
// is told where to stop. A fake player; no AVFoundation. Written before the implementation.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
final class MarkedPreviewPlayer: PreviewPlayback {
    var log: [String] = []
    var position = 0.0
    var duration = 20.0
    var isPlaying = false
    var markIn: Double?
    var markOut: Double?
    func open(path: String, kind: MediaKind) { log.append("open"); position = 0; isPlaying = false }
    func play() { log.append("play"); isPlaying = true }
    func pause() { log.append("pause"); isPlaying = false }
    func seek(to seconds: Double) { log.append("seek \(seconds)"); position = seconds }
    func setLoops(_ on: Bool) { log.append("loops \(on)") }
    func setMuted(_ on: Bool) {}
    func close() { log.append("close"); isPlaying = false }
    func setMarks(in markIn: Double?, out markOut: Double?) { self.markIn = markIn; self.markOut = markOut; log.append("marks \(markIn.map { "\($0)" } ?? "-") \(markOut.map { "\($0)" } ?? "-")") }
}

@MainActor
@Suite struct UI007d_PreviewMarksTests {
    private func video(markIn: Double? = 5, markOut: Double? = 15) -> MediaAsset {
        MediaAsset(name: "loop", kind: .video, path: "/m/loop.mov", duration: 20, markIn: markIn, markOut: markOut)
    }

    @Test func thePlayerIsToldTheMarksOfTheItemItOpens() {
        let player = MarkedPreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: true)
        model.select(video())
        #expect(player.markIn == 5 && player.markOut == 15)
        model.select(nil)
        model.select(video(markIn: nil, markOut: nil))
        #expect(player.markIn == nil && player.markOut == nil)
    }

    @Test func playingFromBeforeTheInMarkStartsAtTheInMark() {
        let player = MarkedPreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: true)
        model.select(video())
        model.togglePlay()
        #expect(player.log.suffix(2) == ["seek 5.0", "play"] && player.isPlaying)
    }

    @Test func playingFromAtOrAfterTheOutMarkStartsAgainAtTheInMark() {
        let player = MarkedPreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: true)
        model.select(video())
        player.position = 15
        model.togglePlay()
        #expect(player.log.suffix(2) == ["seek 5.0", "play"])
        model.togglePlay()                                       // pause
        player.position = 19
        model.togglePlay()
        #expect(player.log.suffix(2) == ["seek 5.0", "play"])
    }

    @Test func playingFromInsideTheMarksPlaysOnFromThere() {
        let player = MarkedPreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: true)
        model.select(video())
        player.position = 9
        model.togglePlay()
        #expect(player.log.suffix(1) == ["play"] && player.position == 9)
    }

    @Test func aClipWithNoMarksPlaysAsBefore() {
        let player = MarkedPreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: true)
        model.select(video(markIn: nil, markOut: nil))
        player.position = 7
        model.togglePlay()
        #expect(player.log.suffix(1) == ["play"] && player.position == 7)
        #expect(model.startPosition == 0)
    }

    @Test func theStartIsTheInMarkForRestartAndStop() {
        let model = MediaPreviewModel(player: MarkedPreviewPlayer(), silent: true)
        let a = video()
        model.select(a)
        #expect(model.startPosition == 5)
        var cleared = a; cleared.markIn = nil
        model.select(cleared)
        #expect(model.startPosition == 0)                        // the same item: the marks are updated, not reopened
    }

    @Test func scrubbingIsFreeOutsideTheMarksSoMarksCanBeSetAnywhere() {
        let player = MarkedPreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: true)
        model.select(video())
        model.seek(to: 1)
        #expect(player.position == 1)
        model.seek(to: 19)
        #expect(player.position == 19)
    }

    @Test func editingTheMarksOfTheSelectedItemUpdatesThePlayerWithoutReopeningIt() {
        let player = MarkedPreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: true)
        let a = video()
        model.select(a)
        let opens = player.log.filter { $0 == "open" }.count
        var edited = a; edited.markOut = 12
        model.select(edited)
        #expect(player.markOut == 12 && player.log.filter { $0 == "open" }.count == opens)
        #expect(model.asset?.markOut == 12)
    }
}
