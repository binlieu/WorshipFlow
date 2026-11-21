// UI-005a (debug builds only): `UI_SNAPSHOT_DESIGN=1` with the ui-snapshots hook (and `UI_SNAPSHOT_SDI=1`, `UI_SNAPSHOT_STAGEMSG` unset)
// captures the app at exactly 1440 x 900 points at 2x, in the state of each design picture as closely as the data allows: Show in
// dark (`01-operator-show`), with the Quick edit tab (`01b`), in light (`09`), and the component board (`08`, `10`) drawn by
// `ComponentsBoard` in a separate window of the design's size. Sample content is plain data with the design's names; the media
// are generated gradients and one test clip. Pictures are compared by scripts/compare-design.sh, by hand.
#if DEBUG
import AppKit
import SwiftUI
import Domain
import OperatorCore

extension AppModel {
    static let designSong = """
    Verse 1:
    Amazing grace, how sweet the sound
    That saved a wretch like me
    I once was lost, but now am found
    Was blind, but now I see

    Chorus:
    My chains are gone, I've been set free
    My God, my Savior has ransomed me
    And like a flood His mercy reigns
    Unending love, amazing grace
    My chains are gone, I've been set free
    My God, my Savior has ransomed me
    And like a flood His mercy reigns
    Unending love, amazing grace

    Verse 2:
    'Twas grace that taught my heart to fear
    And grace my fears relieved
    How precious did that grace appear
    The hour I first believed

    Ending:
    Amazing grace, amazing grace
    """
    static let designSongVI = """
    Verse 1:
    Ân điển lạ lùng thay
    Đã cứu vớt tôi
    Tôi từng lạc mất, nay được tìm thấy
    Từng mù lòa, nay tôi thấy

    Chorus:
    Xiềng xích đã tan, tôi được tự do
    Chúa tôi, Cứu Chúa tôi đã chuộc tôi
    Như dòng nước lũ ơn thương xót
    Tình yêu vô tận, ân điển lạ lùng
    Xiềng xích đã tan, tôi được tự do
    Chúa tôi, Cứu Chúa tôi đã chuộc tôi
    Như dòng nước lũ ơn thương xót
    Tình yêu vô tận, ân điển lạ lùng

    Verse 2:
    Chính ân điển dạy lòng tôi kính sợ
    Và ân điển xua tan sợ hãi
    Ân điển ấy quý báu dường bao
    Giờ tôi mới tin

    Ending:
    Ân điển lạ lùng, ân điển lạ lùng
    """

    /// A gradient picture written as PNG (the design's backgrounds are gradients).
    private static func gradientPNG(_ url: URL, _ a: NSColor, _ b: NSColor, size: Int = 640) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: size, height: size * 9 / 16, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue),
              let gradient = CGGradient(colorsSpace: space, colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1]) else { return }
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size * 9 / 16), options: [])
        if let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) { try? data.write(to: url) }
    }

    /// The design's seven bin tiles: one clip (the test loop) and six generated pictures, named as in the design.
    static func designMediaList(in dir: String) -> String {
        let folder = URL(fileURLWithPath: dir).appendingPathComponent("design-media")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var paths: [String] = []
        let clip = folder.appendingPathComponent("Waves — teal.mov")
        let source = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UI_SNAPSHOT_CLIP"] ?? "TestMedia/loop-1080p5994.mov")
        if !FileManager.default.fileExists(atPath: clip.path) { try? FileManager.default.copyItem(at: source, to: clip) }
        paths.append(clip.path)
        let tiles: [(String, NSColor, NSColor)] = [
            ("Deep blue drift", NSColor(red: 0.12, green: 0.44, blue: 0.56, alpha: 1), NSColor(red: 0.02, green: 0.06, blue: 0.12, alpha: 1)),
            ("Violet haze", NSColor(red: 0.23, green: 0.16, blue: 0.36, alpha: 1), NSColor(red: 0.02, green: 0.06, blue: 0.12, alpha: 1)),
            ("Dawn light", NSColor(red: 0.48, green: 0.29, blue: 0.11, alpha: 1), NSColor(red: 0.04, green: 0.05, blue: 0.10, alpha: 1)),
            ("Soft particles", NSColor(red: 0.21, green: 0.31, blue: 0.43, alpha: 1), NSColor(red: 0.04, green: 0.09, blue: 0.15, alpha: 1)),
            ("Ocean slow", NSColor(red: 0.06, green: 0.30, blue: 0.36, alpha: 1), NSColor(red: 0.02, green: 0.13, blue: 0.22, alpha: 1)),
            ("Night sky", NSColor(red: 0.11, green: 0.16, blue: 0.29, alpha: 1), NSColor(red: 0.04, green: 0.06, blue: 0.13, alpha: 1)),
        ]
        for (name, a, b) in tiles {
            let url = folder.appendingPathComponent("\(name).png")
            gradientPNG(url, a, b)
            paths.append(url.path)
        }
        return paths.joined(separator: ",")
    }

    static func designPropPath(in dir: String) -> String {
        let url = URL(fileURLWithPath: dir).appendingPathComponent("design-media/Church logo bug.png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        gradientPNG(url, NSColor(red: 0.26, green: 0.85, blue: 0.72, alpha: 1), NSColor(red: 0.30, green: 0.60, blue: 0.93, alpha: 1), size: 160)
        return url.path
    }

    func runDesignScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void, window: NSWindow?) async {
        guard let workspace else { note("design: no workspace"); return }
        // The rest of the design's sample content: songs, two more libraries, the service order.
        let songs = ["How Great Thou Art", "10,000 Reasons", "Great Is Thy Faithfulness"]
        var ids: [String: UUID] = [:]
        for title in songs {
            if let p = await workspace.importLyrics(title: title, primaryText: "Line one of \(title)\nLine two of \(title)", secondaryText: nil, maxLines: 2) { ids[title] = p.id }
        }
        let keep = workspace.selectedLibraryID
        await workspace.createLibrary(name: "Sermons")
        await workspace.createLibrary(name: "Announcements")
        if let keep { await workspace.selectLibrary(keep) }
        if let id = ids["How Great Thou Art"] { await workspace.addToPlaylist(id) }
        if let id = ids["10,000 Reasons"] { await workspace.addToPlaylist(id) }
        await workspace.addHeader("Message")
        await workspace.addHeader("Response")
        if let id = ids["Great Is Thy Faithfulness"] { await workspace.addToPlaylist(id) }
        if let playlist = workspace.playlists.first(where: { $0.id == workspace.selectedPlaylistID }) { await workspace.renamePlaylist(id: playlist.id, to: "Sunday 9:00") }
        if let amazing = workspace.playlistItems.first(where: { $0.title == "Amazing Grace" }) { await workspace.openPlaylistItem(amazing.id) }
        window?.setContentSize(NSSize(width: 1440, height: 900))
        window?.center()
        workspace.setMode(.show)
        workspace.selectSlide(2)
        await workspace.goLive()
        workspace.selectSlide(3)
        try? await Task.sleep(for: .seconds(1.5))
        note("design: window \(window.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none"), live \(workspace.show.liveIndex.map(String.init) ?? "-"), slides \(workspace.slides.count)")
        setAppearance(.dark)
        await capture("show-dark")
        openQuickEdit()
        try? await Task.sleep(for: .milliseconds(500))
        await capture("show-quick-edit")
        closeQuickEdit()
        setAppearance(.light)
        await capture("show-light")
        setAppearance(.dark)
        for (name, scheme) in [("components-dark", ColorScheme.dark), ("components-light", ColorScheme.light)] {
            await captureBoard(name: name, scheme: scheme, note: note)
        }
    }

    /// The component board in its own window of the design's size (1440 x 754 points), drawn from the layer tree at 2x.
    func captureBoard(name: String, scheme: ColorScheme, note: @MainActor (String) -> Void) async {
        let size = NSSize(width: 1440, height: 754)
        let host = NSHostingView(rootView: ComponentsBoard(light: scheme == .light).preferredColorScheme(scheme).frame(width: size.width, height: size.height))
        let board = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        board.isReleasedWhenClosed = false
        board.contentView = host
        board.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        board.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(1.2))
        host.layoutSubtreeIfNeeded()
        board.displayIfNeeded()
        guard let layer = (host.superview ?? host).layer, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: 2880, height: 1508, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { board.close(); return }
        ctx.scaleBy(x: 2, y: 2)
        layer.render(in: ctx)
        if let image = ctx.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), let dir = Self.snapshotDirectory {
            try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(ProcessInfo.processInfo.environment["UI_SNAPSHOT_PREFIX"] ?? "UI-005a")-\(name).png"))
            note("design: wrote \(name).png")
        }
        board.close()
    }
}
#endif
