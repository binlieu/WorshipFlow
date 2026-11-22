// UI-005d (debug builds only): `UI_SNAPSHOT_UIMEDIA=1` together with `UI_SNAPSHOT_DESIGN=1` and the ui-snapshots hook captures the Media
// mode at 1440 x 900 points in the state of docs/UI/screens/05-media-audio.png as far as today's data allows: fifteen bin tiles in
// the design's order (eight clips, seven pictures; every clip is the same test file under another name), the first one the live
// background and the one the strip shows, a sound playing, dark and light. Rectangles go to <prefix>-media-*.rects.json for
// scripts/compare-rects.py with scripts/design-map-media.json. Generated media only; nothing of the owner's library is used.
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import OperatorCore

extension AppModel {
    /// A 271 s mono sine tone (04:31, as the design names it) as a PCM WAV file (the sound the design's Audio cue card plays).
    private static func toneWAV(_ url: URL) {
        let rate = 11_025, seconds = 271
        var pcm = Data(capacity: rate * seconds * 2)
        for n in 0..<(rate * seconds) {
            let v = Int16(6_000 * sin(2 * Double.pi * 220 * Double(n) / Double(rate)))
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        func le32(_ x: Int) -> [UInt8] { (0..<4).map { UInt8((x >> (8 * $0)) & 0xFF) } }
        func le16(_ x: Int) -> [UInt8] { (0..<2).map { UInt8((x >> (8 * $0)) & 0xFF) } }
        var header = Data("RIFF".utf8)
        header.append(contentsOf: le32(36 + pcm.count)); header.append(Data("WAVEfmt ".utf8))
        header.append(contentsOf: le32(16) + le16(1) + le16(1) + le32(rate) + le32(rate * 2) + le16(2) + le16(16))
        header.append(Data("data".utf8)); header.append(contentsOf: le32(pcm.count))
        try? (header + pcm).write(to: url)
    }

    private static func gradient(_ url: URL, _ a: NSColor, _ b: NSColor) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: 640, height: 360, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue),
              let g = CGGradient(colorsSpace: space, colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1]) else { return }
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 640, y: 360), options: [])
        if let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    func runMediaDesignScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void, window: NSWindow?) async {
        guard let workspace, let media else { note("uimedia: no models"); return }
        for asset in media.assets { await media.remove(asset.id) }
        let folder = URL(fileURLWithPath: Self.snapshotDirectory ?? NSTemporaryDirectory()).appendingPathComponent("uimedia-files")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let clip = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UI_SNAPSHOT_CLIP"] ?? "TestMedia/loop-1080p5994.mov")
        let tones: [(NSColor, NSColor)] = [
            (NSColor(red: 0.12, green: 0.44, blue: 0.56, alpha: 1), NSColor(red: 0.02, green: 0.06, blue: 0.12, alpha: 1)),
            (NSColor(red: 0.21, green: 0.31, blue: 0.43, alpha: 1), NSColor(red: 0.04, green: 0.09, blue: 0.15, alpha: 1)),
            (NSColor(red: 0.48, green: 0.29, blue: 0.11, alpha: 1), NSColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1)),
            (NSColor(red: 0.06, green: 0.30, blue: 0.36, alpha: 1), NSColor(red: 0.02, green: 0.13, blue: 0.22, alpha: 1)),
            (NSColor(red: 0.23, green: 0.16, blue: 0.36, alpha: 1), NSColor(red: 0.02, green: 0.06, blue: 0.12, alpha: 1)),
        ]
        // The design's fifteen tiles in order; "v" = a clip, "p" = a picture.
        let tiles: [(String, String)] = [
            ("Waves — teal.mov", "v"), ("Deep blue drift", "v"), ("Violet haze", "v"), ("Dawn light", "v"), ("Soft particles", "v"),
            ("Ocean slow", "v"), ("Sanctuary still", "p"), ("Cross sunrise", "p"), ("Welcome card", "p"), ("Offering card", "p"),
            ("Teal gradient", "p"), ("Night sky", "v"), ("Candle bokeh", "v"), ("Mountains", "p"), ("Baptism title", "p"),
        ]
        var urls: [URL] = []
        for (i, tile) in tiles.enumerated() {
            if tile.1 == "v" {
                let url = folder.appendingPathComponent(tile.0 + (tile.0.hasSuffix(".mov") ? ".mov" : ".mov"))
                if !FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.copyItem(at: clip, to: url) }
                urls.append(url)
            } else {
                let url = folder.appendingPathComponent(tile.0 + ".png")
                let t = tones[i % tones.count]
                Self.gradient(url, t.0, t.1)
                urls.append(url)
            }
        }
        let tone = folder.appendingPathComponent("Be Thou My Vision — instrumental.wav")
        Self.toneWAV(tone)
        for url in urls { addMedia([url]); try? await Task.sleep(for: .milliseconds(700)) }
        addMedia([tone])
        try? await Task.sleep(for: .seconds(2))
        window?.setContentSize(NSSize(width: 1440, height: 900))
        window?.center()
        workspace.setMode(.media)
        media.kindFilter = nil
        if let waves = media.assets.first(where: { $0.name == "Waves — teal.mov" }) {
            media.setBackground(waves.id)
            selectBinItem(waves.id)
            try? await Task.sleep(for: .seconds(1))
            binPreview?.seek(to: 11.4)
        }
        if let audio, let sound = audio.assets.first { audio.play(sound.id); try? await Task.sleep(for: .seconds(1)); audio.seek(sound.id, to: 134) }
        try? await Task.sleep(for: .seconds(2))
        note("uimedia: bin \(media.assets.map(\.name))")
        setAppearance(.dark)
        await capture("media-dark")
        setAppearance(.light)
        await capture("media-light")
        // UI-006d: the design's offline callout (a clip whose file is then taken away) and a collection ("Announcement loop"), captured on their own.
        let gone = folder.appendingPathComponent("Baptism testimony.png")      // a picture, so the scenario needs no test clip
        try? FileManager.default.removeItem(at: gone)
        Self.gradient(gone, tones[0].0, tones[0].1)
        addMedia([gone])
        try? await Task.sleep(for: .seconds(1.5))
        try? FileManager.default.removeItem(at: gone)
        let loop = media.assets.filter { ["Dawn light", "Offering card", "Mountains"].contains($0.name) }.map(\.id)
        if let id = media.createCollection("Announcement loop", adding: loop) { media.collectionFilter = id }
        await media.refreshOffline()
        note("uimedia: offline \(media.offlineAssets.map(\.name)), collections \(media.collections.items.map(\.name))")
        setAppearance(.dark)
        await capture("media-offline-dark")
        setAppearance(.light)
        await capture("media-offline-light")
        media.collectionFilter = nil
        setAppearance(.dark)
    }
}
#endif
