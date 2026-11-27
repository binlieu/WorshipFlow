// UI-005h: a tool run by hand (not by the check).
//   wf-looks-probe looks <out dir> <07 design rects json> [Vendor/Inter/InterVariable.ttf]
//       renders the three role compositions of the design's sample slide at 1920 x 1080 (audience; stage with timer and message band; the
//       broadcast lower third as fill, key and composite over a checkerboard) into PNGs, and writes looks.rects.json: the rectangles of text,
//       plate and bar in the page coordinates of the design dump, for scripts/compare-rects.py with scripts/design-map-looks.json.
//   wf-looks-probe perf | perf-long | compare | gpu | readback: frame time numbers (FIX-J: perf-long uses a long bilingual slide that needs fitting).
//   wf-looks-probe long-pictures <out dir>: that slide on the audience and lower-third looks, as PNGs.
// `wf-looks-probe perf` measures the time to render the three role compositions of
// one slide at 1920 x 1080 into offscreen textures, cold (first frame: shaders, text rasterisation) and warm (steady state), and
// prints the numbers. It asserts nothing: wall-clock time never decides a test.
import Foundation
import Metal
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Domain
import RenderEngine
import SDIEngine

func samples() -> ShowState {
    var state = ShowState()
    state.apply(.load(ShowDeck(presentationID: UUID(), slides: [
        SlideContent(primary: "Through many dangers\ntoils and snares", secondary: "Qua bao hi\u{1EC3}m nguy\ngian kh\u{00F3} th\u{1EED} th\u{00E1}ch"),
        SlideContent(primary: "'Tis grace has brought me safe thus far"),
    ])))
    state.apply(.trigger(index: 0))
    return state
}

/// FIX-J: a bilingual slide long enough to need fitting on the audience screen (invented words).
func longSample() -> ShowState {
    var state = ShowState()
    state.apply(.load(ShowDeck(presentationID: UUID(), slides: [
        SlideContent(primary: "Every morning brings a song of new beginnings and a hope that never fades away, and we sing it again together",
                     secondary: "M\u{1ED7}i s\u{00E1}ng mai l\u{00E0} m\u{1ED9}t b\u{00E0}i ca m\u{1EDB}i v\u{00E0} m\u{1ED9}t ni\u{1EC1}m hy v\u{1ECD}ng kh\u{00F4}ng bao gi\u{1EDD} t\u{1EAF}t"),
    ])))
    state.apply(.trigger(index: 0))
    return state
}

/// Registers the bundled Inter from ./Vendor/Inter (run from the repository root) so the looks are timed in their own font.
func registerInterIfPresent() {
    let url = URL(fileURLWithPath: "Vendor/Inter/InterVariable.ttf")
    guard FileManager.default.fileExists(atPath: url.path) else { print("(Inter not found: timing with a system font)"); return }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}

func perf(long: Bool) throws {
    registerInterIfPresent()
    let state = long ? longSample() : samples()
    let compositor = try Compositor()
    let scenes: [SceneDescription] = [
        SceneComposer.scene(for: .audience, state: state, theme: Theme.fullScreen, look: .standard, props: [], clockText: "9:14"),
        SceneComposer.scene(for: .stage, state: state, theme: Theme.fullScreen, look: .standard, props: [], clockText: "9:14"),
        SceneComposer.scene(for: .broadcast, state: state, theme: Theme.lowerThird, look: .standard, props: [], clockText: "9:14"),
    ]
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1920, height: 1080, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]
    td.storageMode = .private
    let targets = try scenes.map { _ in try { guard let t = compositor.device.makeTexture(descriptor: td) else { throw RenderError.invalidSize }; return t }() }
    func frame() throws -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        guard let cb = compositor.makeCommandBuffer() else { throw RenderError.invalidSize }
        for (scene, target) in zip(scenes, targets) { try compositor.encode(scene: scene, into: target, video: nil, commandBuffer: cb) }
        cb.commit(); cb.waitUntilCompleted()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
    let cold = try frame()
    // WARMED-BEGIN (FIX-J: only builds with the text warmer)
    let preparedAt = DispatchTime.now().uptimeNanoseconds
    TextWarmer.warmNow(scenes: scenes.map { ($0, 1920, 1080) })
    let prepared = Double(DispatchTime.now().uptimeNanoseconds - preparedAt) / 1_000_000
    let warmCompositor = try Compositor()
    let warmTargets = try scenes.map { _ in try { guard let t = warmCompositor.device.makeTexture(descriptor: td) else { throw RenderError.invalidSize }; return t }() }
    do {
        let start = DispatchTime.now().uptimeNanoseconds
        guard let cb = warmCompositor.makeCommandBuffer() else { throw RenderError.invalidSize }
        for (scene, target) in zip(scenes, warmTargets) { try warmCompositor.encode(scene: scene, into: target, video: nil, commandBuffer: cb) }
        cb.commit(); cb.waitUntilCompleted()
        print(String(format: "text prepared ahead (background): %.3f ms; first frame of a compositor after that: %.3f ms", prepared, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000))
    }
    // WARMED-END
    for _ in 0..<20 { _ = try frame() }
    var times: [Double] = []
    for _ in 0..<600 { times.append(try frame()) }
    times.sort()
    let mean = times.reduce(0, +) / Double(times.count)
    print(String(format: "three-role 1920x1080 frame: cold %.3f ms; warm over %d frames: mean %.3f ms, median %.3f ms, p99 %.3f ms, worst %.3f ms",
                 cold, times.count, mean, times[times.count / 2], times[Int(Double(times.count) * 0.99)], times.last ?? 0))
}

/// The same measurement with a frame read back to memory, for the new looks and for the Classic ones (the earlier looks, built from the
/// earlier styles) drawn by the same build, so the two can be compared directly.
func perfCompare() throws {
    let state = samples()
    var old = SceneStyles()
    old.stageCurrent.fontSize = 96.001                     // not the standard styles: takes the earlier stage path
    let looks: [(String, [SceneDescription])] = [
        ("design looks", [
            SceneComposer.scene(for: .audience, state: state, theme: Theme.fullScreen, look: .standard, props: [], clockText: "9:14"),
            SceneComposer.scene(for: .stage, state: state, theme: Theme.fullScreen, look: .standard, props: [], clockText: "9:14"),
            SceneComposer.scene(for: .broadcast, state: state, theme: Theme.lowerThird, look: .standard, props: [], clockText: "9:14")]),
        ("classic looks", [
            SceneComposer.scene(for: .audience, state: state, theme: Theme.classicFullScreen, look: .standard, props: [], clockText: "9:14"),
            SceneComposer.scene(for: .stage, state: state, clockText: "9:14", styles: old),
            SceneComposer.scene(for: .broadcast, state: state, theme: Theme.classicLowerThird, look: .standard, props: [], clockText: "9:14")]),
    ]
    for (name, scenes) in looks {
        let compositor = try Compositor()
        func frame() throws -> Double {
            let start = DispatchTime.now().uptimeNanoseconds
            for scene in scenes { _ = try compositor.renderImage(scene: scene, width: 1920, height: 1080) }
            return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        }
        let cold = try frame()
        for _ in 0..<5 { _ = try frame() }
        var times: [Double] = []
        for _ in 0..<100 { times.append(try frame()) }
        times.sort()
        print(String(format: "%@ with readback, three roles: cold %.3f ms; warm mean %.3f ms, median %.3f ms, p99 %.3f ms", name, cold, times.reduce(0, +) / Double(times.count), times[times.count / 2], times[Int(Double(times.count) * 0.99)]))
    }
}

/// GPU time of each scene alone (the command buffer's own start and end), drawn into a shared-storage target as the SDI outputs do.
func perfGPU() throws {
    let state = samples()
    var old = SceneStyles()
    old.stageCurrent.fontSize = 96.001
    let scenes: [(String, SceneDescription)] = [
        ("design audience", SceneComposer.scene(for: .audience, state: state, theme: Theme.fullScreen, look: .standard, props: [], clockText: "9:14")),
        ("classic audience", SceneComposer.scene(for: .audience, state: state, theme: Theme.classicFullScreen, look: .standard, props: [], clockText: "9:14")),
        ("design stage", SceneComposer.scene(for: .stage, state: state, theme: Theme.fullScreen, look: .standard, props: [], clockText: "9:14")),
        ("classic stage", SceneComposer.scene(for: .stage, state: state, clockText: "9:14", styles: old)),
        ("design broadcast", SceneComposer.scene(for: .broadcast, state: state, theme: Theme.lowerThird, look: .standard, props: [], clockText: "9:14")),
        ("classic broadcast", SceneComposer.scene(for: .broadcast, state: state, theme: Theme.classicLowerThird, look: .standard, props: [], clockText: "9:14")),
    ]
    let compositor = try Compositor()
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1920, height: 1080, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]
    td.storageMode = .shared
    guard let target = compositor.device.makeTexture(descriptor: td) else { throw RenderError.invalidSize }
    for (name, scene) in scenes {
        var bytes = [UInt8](repeating: 0, count: 1920 * 1080 * 4)
        func one() throws -> (cpu: Double, gpu: Double, read: Double) {
            let start = DispatchTime.now().uptimeNanoseconds
            guard let cb = compositor.makeCommandBuffer() else { throw RenderError.invalidSize }
            try compositor.encode(scene: scene, into: target, video: nil, commandBuffer: cb)
            let encoded = DispatchTime.now().uptimeNanoseconds
            cb.commit(); cb.waitUntilCompleted()
            let waited = DispatchTime.now().uptimeNanoseconds
            bytes.withUnsafeMutableBytes { raw in if let base = raw.baseAddress { target.getBytes(base, bytesPerRow: 1920 * 4, from: MTLRegionMake2D(0, 0, 1920, 1080), mipmapLevel: 0) } }
            let read = DispatchTime.now().uptimeNanoseconds
            return (Double(encoded - start) / 1_000_000, (cb.gpuEndTime - cb.gpuStartTime) * 1000, Double(read - waited) / 1_000_000)
        }
        for _ in 0..<10 { _ = try one() }
        var cpu = 0.0, gpu = 0.0, read = 0.0
        for _ in 0..<200 { let r = try one(); cpu += r.cpu; gpu += r.gpu; read += r.read }
        print(String(format: "%@: encode (CPU) %.3f ms, GPU %.3f ms, readback %.3f ms per frame", name, cpu / 200, gpu / 200, read / 200))
    }
}

/// Reading a rendered frame back: the texture's own `getBytes` against a GPU copy into a shared buffer then a memory copy.
func perfReadback() throws {
    let state = samples()
    let scenes: [(String, SceneDescription)] = [
        ("design audience (gradient)", SceneComposer.scene(for: .audience, state: state, theme: Theme.fullScreen, look: .standard, props: [], clockText: "9:14")),
        ("classic audience (flat)", SceneComposer.scene(for: .audience, state: state, theme: Theme.classicFullScreen, look: .standard, props: [], clockText: "9:14")),
    ]
    let compositor = try Compositor()
    let device = compositor.device
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1920, height: 1080, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]
    td.storageMode = .shared
    guard let target = device.makeTexture(descriptor: td), let buffer = device.makeBuffer(length: 1920 * 1080 * 4, options: .storageModeShared),
          let queue = device.makeCommandQueue() else { throw RenderError.invalidSize }
    var bytes = [UInt8](repeating: 0, count: 1920 * 1080 * 4)
    for (name, scene) in scenes {
        var getBytes = 0.0, viaBuffer = 0.0
        for i in 0..<110 {
            guard let cb = compositor.makeCommandBuffer() else { throw RenderError.invalidSize }
            try compositor.encode(scene: scene, into: target, video: nil, commandBuffer: cb)
            cb.commit(); cb.waitUntilCompleted()
            let t0 = DispatchTime.now().uptimeNanoseconds
            bytes.withUnsafeMutableBytes { raw in if let base = raw.baseAddress { target.getBytes(base, bytesPerRow: 1920 * 4, from: MTLRegionMake2D(0, 0, 1920, 1080), mipmapLevel: 0) } }
            let t1 = DispatchTime.now().uptimeNanoseconds
            let tb = DispatchTime.now().uptimeNanoseconds
            guard let cb2 = compositor.makeCommandBuffer() else { throw RenderError.invalidSize }
            try compositor.encode(scene: scene, into: target, video: nil, commandBuffer: cb2)
            _ = queue
            guard let blit = cb2.makeBlitCommandEncoder() else { throw RenderError.invalidSize }
            blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: 1920, height: 1080, depth: 1),
                      to: buffer, destinationOffset: 0, destinationBytesPerRow: 1920 * 4, destinationBytesPerImage: 1920 * 1080 * 4)
            blit.endEncoding()
            cb2.commit(); cb2.waitUntilCompleted()
            let t2 = DispatchTime.now().uptimeNanoseconds
            bytes.withUnsafeMutableBytes { raw in if let base = raw.baseAddress { memcpy(base, buffer.contents(), 1920 * 1080 * 4) } }
            let t3 = DispatchTime.now().uptimeNanoseconds
            if i >= 10 { getBytes += Double(t1 - t0) / 1_000_000; viaBuffer += Double(t3 - tb) / 1_000_000 }
        }
        print(String(format: "%@: render+wait then getBytes: read %.3f ms; render+blit+wait then memcpy: whole path %.3f ms (a render alone is about 0.1 ms)", name, getBytes / 100, viaBuffer / 100))
    }
}

// MARK: looks

func png(_ frame: RenderedFrame, to url: URL, transform: ((inout [UInt8]) -> Void)? = nil) throws {
    try png(frame.bgra, width: frame.width, height: frame.height, to: url, transform: transform)
}

func png(_ pixels: [UInt8], width: Int, height: Int, to url: URL, transform: ((inout [UInt8]) -> Void)? = nil) throws {
    var bytes = pixels
    transform?(&bytes)
    guard let provider = CGDataProvider(data: Data(bytes) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw RenderError.invalidSize }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw RenderError.invalidSize }
}

func looks(out: String, designPath: String, fontPath: String?) throws {
    if let fontPath {
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: fontPath) as CFURL, .process, &error)
    }
    let dir = URL(fileURLWithPath: out, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    // Panel origins in the design dump (page coordinates), so the app's rectangles can be compared with the mockup's directly.
    struct Row: Decodable { let path: String; let x: Double; let y: Double }
    let design = try JSONDecoder().decode([Row].self, from: Data(contentsOf: URL(fileURLWithPath: designPath)))
    func origin(_ suffix: String) -> (x: Double, y: Double) { design.first { $0.path.hasSuffix(suffix) }.map { ($0.x, $0.y) } ?? (0, 0) }
    let origins = ["aud": origin("div.g[0]>div[0]>div.o[1]"), "stg": origin("div.g[0]>div[1]>div.o[1]"), "lt": origin("div.g[0]>div[2]>div.o.checker[1]"),
                   "key": origin("div.g[0]>div[3]>div.o[1]")]

    let compositor = try Compositor()
    var rects: [[String: Any]] = []
    func add(_ id: String, _ panel: String, _ box: LayoutBox, size: Double? = nil, weight: Int? = nil, radius: Double? = nil) {
        let o = origins[panel] ?? (0, 0)
        var row: [String: Any] = ["id": id, "x": o.x + box.x, "y": o.y + box.y, "w": box.width, "h": box.height]
        if let size { row["fontSize"] = size }
        if let weight { row["fontWeight"] = weight }
        if let radius { row["radius"] = radius }
        rects.append(row)
    }

    // Audience: the full-screen lyrics.
    let audience = SceneComposer.scene(for: .audience, state: samples(), theme: Theme.fullScreen, look: .standard, props: [])
    let a = try compositor.layoutReport(scene: audience, width: 1920, height: 1080)
    for (id, item) in zip(["aud.primary", "aud.secondary"], a.texts) { add(id, "aud", item.box, size: item.fontSize, weight: item.weight) }
    try png(try compositor.renderImage(scene: audience, width: 1920, height: 1080), to: dir.appendingPathComponent("audience.png"))

    // Stage: the built-in layout with a countdown of 10:32, the clock at 9:14 and the message band.
    let timer = ShowTimer(id: UUID(), name: "Sermon", kind: .countdown(seconds: 632))
    let stage = StageComposer.scene(layout: .standard, context: StageContext(state: samples(), now: 0, timeOfDayText: "9:14", timers: [timer],
                                                                              message: "Repeat chorus \u{00D7}2, then bridge", notes: nil))
    let s = try compositor.layoutReport(scene: stage, width: 1920, height: 1080)
    let names: [String: String] = ["Through many dangers\ntoils and snares": "stg.current", "NEXT": "stg.next.label", "'Tis grace has brought me safe thus far": "stg.next",
                                   "9:14": "stg.clock", "10:32": "stg.timer", "Repeat chorus \u{00D7}2, then bridge": "stg.band.text"]
    for item in s.texts {
        let id = names[item.text] ?? (item.text.contains("\u{00B7}") ? "stg.second" : "stg.other")
        add(id, "stg", item.box, size: item.fontSize, weight: item.weight)
    }
    if let band = s.plate { add("stg.band", "stg", band, radius: 0) }
    try png(try compositor.renderImage(scene: stage, width: 1920, height: 1080), to: dir.appendingPathComponent("stage.png"))

    // Broadcast lower third: composite over a checkerboard, the fill signal and the key signal.
    let lower = SceneComposer.scene(for: .broadcast, state: UI_lowerThirdState(), theme: Theme.lowerThird, look: .standard, props: [])
    let l = try compositor.layoutReport(scene: lower, width: 1920, height: 1080)
    for (id, item) in zip(["lt.primary", "lt.secondary"], l.texts) { add(id, "lt", item.box, size: item.fontSize, weight: item.weight) }
    if let plate = l.plate { add("lt.plate", "lt", plate, radius: 19.2) }
    if let bar = l.bar { add("lt.bar", "lt", bar, radius: 5.76) }
    // The key panel is the same composition: the same boxes in the key's own panel.
    for (id, item) in zip(["key.primary", "key.secondary"], l.texts) { add(id, "key", item.box, size: item.fontSize, weight: item.weight) }
    if let plate = l.plate { add("key.plate", "key", plate, radius: 19.2) }
    if let bar = l.bar { add("key.bar", "key", bar, radius: 5.76) }
    let frame = try compositor.renderImage(scene: lower, width: 1920, height: 1080)
    let split = FillKeySplitter.split(bgra: frame.bgra, fillAlphaMode: .premultiplied)
    try png(split.fill, width: 1920, height: 1080, to: dir.appendingPathComponent("broadcast-fill.png"))
    try png(split.key, width: 1920, height: 1080, to: dir.appendingPathComponent("broadcast-key.png"))
    try png(frame, to: dir.appendingPathComponent("broadcast-composite.png")) { bytes in
        // Over a grey checkerboard of 40 px squares, as the previews draw transparency.
        for y in 0..<1080 { for x in 0..<1920 {
            let i = (y * 1920 + x) * 4
            let base: Double = ((x / 40 + y / 40) % 2 == 0) ? 150 : 110
            let a = Double(bytes[i + 3]) / 255
            for c in 0..<3 { bytes[i + c] = UInt8(min(255, Double(bytes[i + c]) + base * (1 - a))) }
            bytes[i + 3] = 255
        } }
    }
    let json = try JSONSerialization.data(withJSONObject: ["rects": rects], options: [.prettyPrinted, .sortedKeys])
    try json.write(to: dir.appendingPathComponent("looks.rects.json"))
    print("wrote \(rects.count) rectangles and four pictures to \(dir.path)")
}

/// FIX-J: the long bilingual slide on the audience look and on the lower-third look (over a checkerboard), 1280 x 720, for the report's pictures.
func longPictures(out: String) throws {
    registerInterIfPresent()
    let dir = URL(fileURLWithPath: out, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let compositor = try Compositor()
    let state = longSample()
    let audience = SceneComposer.scene(for: .audience, state: state, theme: Theme.fullScreen, look: .standard, props: [])
    try png(try compositor.renderImage(scene: audience, width: 1280, height: 720), to: dir.appendingPathComponent("audience-long.png"))
    let lower = SceneComposer.scene(for: .broadcast, state: state, theme: Theme.lowerThird, look: .standard, props: [])
    let frame = try compositor.renderImage(scene: lower, width: 1280, height: 720)
    try png(frame, to: dir.appendingPathComponent("lowerthird-long.png")) { bytes in
        for y in 0..<720 { for x in 0..<1280 {
            let i = (y * 1280 + x) * 4
            let base: Double = ((x / 27 + y / 27) % 2 == 0) ? 150 : 110
            let a = Double(bytes[i + 3]) / 255
            for c in 0..<3 { bytes[i + c] = UInt8(min(255, Double(bytes[i + c]) + base * (1 - a))) }
            bytes[i + 3] = 255
        } }
    }
    print("wrote the long bilingual slide on the audience and lower-third looks to \(dir.path)")
}

func UI_lowerThirdState() -> ShowState {
    var state = ShowState()
    state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Through many dangers, toils and snares",
                                                                             secondary: "Qua bao hi\u{1EC3}m nguy, gian kh\u{00F3} th\u{1EED} th\u{00E1}ch")])))
    state.apply(.trigger(index: 0))
    return state
}

let mode = CommandLine.arguments.dropFirst().first ?? "perf"
switch mode {
case "looks":
    let args = Array(CommandLine.arguments.dropFirst(2))
    guard args.count >= 2 else { FileHandle.standardError.write(Data("usage: wf-looks-probe looks <out dir> <design rects json> [InterVariable.ttf]\n".utf8)); exit(2) }
    try looks(out: args[0], designPath: args[1], fontPath: args.count > 2 ? args[2] : nil)
case "long-pictures":
    guard CommandLine.arguments.count > 2 else { FileHandle.standardError.write(Data("usage: wf-looks-probe long-pictures <out dir>\n".utf8)); exit(2) }
    try longPictures(out: CommandLine.arguments[2])
case "readback": try perfReadback()
case "gpu": try perfGPU()
case "perf": try perf(long: false)
case "perf-long": try perf(long: true)
case "compare": try perfCompare()
default: FileHandle.standardError.write(Data("usage: wf-looks-probe perf\n".utf8)); exit(2)
}
