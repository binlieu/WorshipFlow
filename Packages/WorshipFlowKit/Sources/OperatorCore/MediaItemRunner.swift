// FIX-H items 1 and 6 (UI-005b): what a playlist media item or announcements loop does with the players. The workspace model says what
// the operator chose (`MediaItemCommand`); the runner plays it through two small ports (the foreground clip player and the audio
// player), says whether it started, and runs the loop's one-second decisions. It has no timer of its own: the app calls `tick()`, and
// tests call it with a fake clock and fake players.
//
// A loop owns the foreground only while nobody else has started anything there. Every start on the foreground is counted by the
// player; the loop remembers the count after its own start, so a clip the operator plays from the bin, the dock or a cue (even the
// same picture again) is never replaced, and the loop ends and says so.
import Foundation
import Domain

/// What happened to a command that asked for something to play.
public enum MediaItemOutcome: Equatable, Sendable {
    case ok
    /// It did not start. The text says which file and why, in plain words.
    case failed(String)
}

/// The clip player for the picture layer over the screens (the media bin's own model in the app).
@MainActor
public protocol ForegroundPort: AnyObject {
    /// The bin's name for the item; nil when the bin does not list it.
    func name(of assetID: UUID) -> String?
    /// Listed, and the file can be read now.
    func isReadable(_ assetID: UUID) -> Bool
    /// Plays the item over the screens from its start. Nil when it plays; otherwise the reason it did not.
    func startForeground(_ assetID: UUID) -> String?
    var foregroundAssetID: UUID? { get }
    /// How many times anything has started on the foreground (the bin, the dock, a cue and the loop all count).
    var foregroundStarts: Int { get }
    func setForegroundLoops(_ on: Bool)
    func stopForeground()
}

/// The sound player.
@MainActor
public protocol AudioPlayerPort: AnyObject {
    func name(of assetID: UUID) -> String?
    /// Listed, and the file can be read now.
    func isReadable(_ assetID: UUID) -> Bool
    /// Plays the sound from its start. Nil when it plays; otherwise the reason it did not.
    func startSound(_ assetID: UUID) -> String?
    func stop(_ assetID: UUID)
}

@MainActor
public final class MediaItemRunner {
    fileprivate let foreground: ForegroundPort
    fileprivate let audio: AudioPlayerPort?
    private let preview: (UUID?) -> Void
    private let now: () -> TimeInterval
    private var loop: AnnouncementsSpec?
    private var loopStartedAt: TimeInterval = 0
    private var shownIndex = -1
    private var expectedStarts = 0

    /// The loop ended by itself: the operator cleared the foreground or played something else there. Not called when the model asked
    /// for the loop to stop.
    public var onLoopEnded: (@MainActor () -> Void)?

    public init(foreground: ForegroundPort, audio: AudioPlayerPort?, preview: @escaping (UUID?) -> Void,
                now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.foreground = foreground
        self.audio = audio
        self.preview = preview
        self.now = now
    }

    public var loopIsActive: Bool { loop != nil }

    @discardableResult
    public func handle(_ command: MediaItemCommand) -> MediaItemOutcome {
        switch command {
        case .preview(let spec):
            guard foreground.name(of: spec.assetID) != nil || audio?.name(of: spec.assetID) != nil else { return .failed(Self.missing(spec.name)) }
            preview(spec.assetID)
            return .ok
        case .play(let spec):
            if spec.kind == .audio {
                guard let audio else { return .failed("\"\(spec.name)\" is a sound file, and sound playback is not available in this session. Nothing was played.") }
                guard audio.name(of: spec.assetID) != nil else { return .failed(Self.missing(spec.name)) }
                if let why = audio.startSound(spec.assetID) { return .failed(why) }
                return .ok
            }
            guard foreground.name(of: spec.assetID) != nil else { return .failed(Self.missing(spec.name)) }
            guard foreground.isReadable(spec.assetID) else { return .failed(Self.unreadable(spec.name)) }
            if let why = foreground.startForeground(spec.assetID) { return .failed(why) }
            return .ok
        case .stop(let spec):
            if spec.kind == .audio { audio?.stop(spec.assetID) }
            else if foreground.foregroundAssetID == spec.assetID { foreground.stopForeground() }
            return .ok
        case .startLoop(let spec): return start(spec)
        case .stopLoop:
            stopLoop()
            return .ok
        }
    }

    fileprivate static func missing(_ name: String) -> String {
        "\"\(name)\" is not in the media bin any more. Add the file to the bin again, then put it back in the playlist."
    }

    fileprivate static func unreadable(_ name: String) -> String {
        "\"\(name)\" is in the media bin but its file cannot be read now. Check that the drive or folder is connected, or add the file to the bin again. The screens were not changed."
    }

    private func start(_ spec: AnnouncementsSpec) -> MediaItemOutcome {
        stopLoop()
        guard let first = spec.items.firstIndex(where: { foreground.isReadable($0.assetID) }) else {
            return .failed("None of the pictures or the video of \"\(spec.label)\" can be opened: they are missing from the media bin or their files cannot be read. The screens were not changed.")
        }
        if let why = foreground.startForeground(spec.items[first].assetID) { return .failed(why) }
        loop = spec
        loopStartedAt = now()
        shownIndex = first
        expectedStarts = foreground.foregroundStarts
        if spec.isVideoLoop { foreground.setForegroundLoops(true) }
        return .ok
    }

    /// One decision of the loop. Call about once a second while a loop is live.
    public func tick() {
        guard let loop else { return }
        guard foreground.foregroundAssetID != nil, foreground.foregroundStarts == expectedStarts else {
            self.loop = nil                                   // cleared, or the operator played something there: it is theirs now
            onLoopEnded?()
            return
        }
        let index = loop.pictureIndex(afterSeconds: now() - loopStartedAt)
        guard index != shownIndex, loop.items.indices.contains(index), foreground.isReadable(loop.items[index].assetID) else { return }
        guard foreground.startForeground(loop.items[index].assetID) == nil else { return }
        shownIndex = index
        expectedStarts = foreground.foregroundStarts
    }

    private func stopLoop() {
        guard loop != nil else { return }
        loop = nil
        if foreground.foregroundAssetID != nil, foreground.foregroundStarts == expectedStarts {      // still the loop's own picture
            foreground.setForegroundLoops(false)
            foreground.stopForeground()
        }
    }
}

extension MediaItemRunner {
    /// FIX-H item 6: whether an item could play right now, asked before the screens change. Nil when it can; otherwise the plain reason,
    /// naming the file. A file the bin lists but the disk cannot read counts as one that cannot play.
    public func preflight(_ kind: PlaylistItemKind) -> String? {
        switch kind {
        case .media(let spec):
            if spec.kind == .audio {
                guard audio != nil else { return "\"\(spec.name)\" is a sound file, and sound playback is not available in this session. Nothing was played." }
                guard audio?.name(of: spec.assetID) != nil else { return Self.missing(spec.name) }
                return audio?.isReadable(spec.assetID) == true ? nil : Self.unreadable(spec.name)
            }
            guard foreground.name(of: spec.assetID) != nil else { return Self.missing(spec.name) }
            return foreground.isReadable(spec.assetID) ? nil : Self.unreadable(spec.name)
        case .announcements(let spec):
            return spec.items.contains { foreground.isReadable($0.assetID) } ? nil
                : "None of the pictures or the video of \"\(spec.label)\" can be opened: they are missing from the media bin or their files cannot be read. The screens were not changed."
        default:
            return nil
        }
    }
}
