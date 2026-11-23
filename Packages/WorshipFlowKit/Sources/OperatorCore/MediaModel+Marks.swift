// UI-007d (MEDIA): setting, typing and clearing a clip's mark in and mark out. The marks are stored on the bin item (`mediaAsset.markIn` and
// `markOut`, schema v15); they are read when a clip is chosen for playing (`MediaSelection.forPlayback`), so editing them never changes a
// clip that is on air now: the new marks apply from its next start. Foundation and Domain only.
import Foundation
import Domain
import Persistence

extension MediaModel {
    /// Sets the in mark (nil clears it). The time is seconds into the clip; the caller reads it from the playhead or from typed text.
    public func setMarkIn(_ time: Double?, for id: UUID) async {
        guard let asset = markableAsset(id) else { return }
        await storeMarks(of: asset, markIn: time, markOut: asset.markOut)
    }

    /// Sets the out mark (nil clears it).
    public func setMarkOut(_ time: Double?, for id: UUID) async {
        guard let asset = markableAsset(id) else { return }
        await storeMarks(of: asset, markIn: asset.markIn, markOut: time)
    }

    /// Clears both marks: the whole clip plays.
    public func clearMarks(for id: UUID) async {
        guard let asset = markableAsset(id) else { return }
        await storeMarks(of: asset, markIn: nil, markOut: nil)
    }

    /// What the strip says about a clip's marks: "In 00:02.0 · Out 00:08.5", or nil when it has none.
    public static func marksSummary(of asset: MediaAsset) -> String? {
        var parts: [String] = []
        if let i = asset.markIn { parts.append("In \(MediaTimeText.format(i))") }
        if let o = asset.markOut { parts.append("Out \(MediaTimeText.format(o))") }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    private func markableAsset(_ id: UUID) -> MediaAsset? {
        guard let asset = assets.first(where: { $0.id == id }) else {
            report("Marks are kept for items in the media bin. Add this item to the bin first.")
            return nil
        }
        switch asset.kind {
        case .video: return asset
        case .audio:
            report("\"\(asset.name)\" is a sound. In and out marks are used for videos; the audio player does not play from a mark yet.")
            return nil
        case .image:
            report("\"\(asset.name)\" is a picture. It has no time to mark.")
            return nil
        }
    }

    private func storeMarks(of asset: MediaAsset, markIn: Double?, markOut: Double?) async {
        if let markIn, let markOut, markIn >= markOut {
            report("The in mark must be before the out mark (\(MediaTimeText.format(markOut))). Clear the other mark or choose another time.")
            return
        }
        guard MediaMarks.isValid(markIn: markIn, markOut: markOut, length: asset.duration) else {
            let length = asset.duration.map { " The clip is \(MediaTimeText.format($0)) long." } ?? ""
            report("That time is not inside the clip.\(length)")
            return
        }
        guard await attempt("save the marks of \"\(asset.name)\"", { try await self.store.setMediaMarks(markIn: markIn, markOut: markOut, forAsset: asset.id) }) != nil else { return }
        await reload()
    }
}
