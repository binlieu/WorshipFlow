// UI-005h: fixtures shared by the migration, matte and look tests. The user themes below use only what the model had before
// this slice (no weight, no plate, no gradient); their rendered digests were recorded with the code of the commit before UI-005h
// (see `UI005h_Golden`), and every later build must reproduce them.
import Foundation
import CoreText
import Domain
import RenderEngine

enum UI005hFixtures {
    /// The design's sample slide (07-output-looks): "Amazing Grace, chorus, English and Vietnamese".
    static let sampleSlide = SlideContent(primary: "Through many dangers\ntoils and snares",
                                          secondary: "Qua bao hi\u{1EC3}m nguy\ngian kh\u{00F3} th\u{1EED} th\u{00E1}ch")
    static let sampleNext = SlideContent(primary: "'Tis grace has brought me safe thus far")
    /// The lower third's lines: one line each, as the design shows them.
    static let lowerThirdSlide = SlideContent(primary: "Through many dangers, toils and snares",
                                              secondary: "Qua bao hi\u{1EC3}m nguy, gian kh\u{00F3} th\u{1EED} th\u{00E1}ch")

    static func live(_ slide: SlideContent = sampleSlide, next: SlideContent? = sampleNext) -> ShowState {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(uuidString: "00000000-0000-4000-8000-0000000000A1") ?? UUID(),
                                   slides: [slide] + (next.map { [$0] } ?? []))))
        state.apply(.trigger(index: 0))
        return state
    }

    private static func id(_ n: Int) -> UUID { UUID(uuidString: "7E57F1A0-0000-4000-8000-00000000000\(n)") ?? UUID() }

    /// Themes a church could have made with the editor before UI-005h.
    static let userThemes: [Theme] = [
        Theme(id: id(1), name: "Sunday blue", background: .color(ColorRGBA(red: 0.05, green: 0.12, blue: 0.4)),
              primary: TextBlock(style: TextStyle(fontName: "Helvetica Neue", fontSize: 90, color: .white, outlineWidth: 5, outlineColor: .black),
                                 frame: NormalizedRect(x: 0.05, y: 0.15, width: 0.9, height: 0.35), alignment: .center, verticalAlignment: .bottom),
              secondary: TextBlock(style: TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: ColorRGBA(red: 1, green: 0.9, blue: 0.3), outlineWidth: 3),
                                   frame: NormalizedRect(x: 0.05, y: 0.52, width: 0.9, height: 0.3), alignment: .center, verticalAlignment: .top)),
        Theme(id: id(2), name: "Loop with shadow", background: .media,
              primary: TextBlock(style: TextStyle(fontName: "Georgia", fontSize: 100, color: ColorRGBA(red: 0.95, green: 0.95, blue: 0.9),
                                                  shadow: TextShadow(color: ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0.7), offsetX: 3, offsetY: 6, blur: 12)),
                                 frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.4), alignment: .leading, verticalAlignment: .center),
              secondary: nil),
        Theme(id: id(3), name: "Keyed plain", background: .transparent,
              primary: TextBlock(style: TextStyle(fontName: "Helvetica Neue", fontSize: 54, color: .white, outlineWidth: 3, outlineColor: .black),
                                 frame: NormalizedRect(x: 0.08, y: 0.72, width: 0.84, height: 0.12), alignment: .leading, verticalAlignment: .bottom),
              secondary: TextBlock(style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: ColorRGBA(red: 1, green: 0.86, blue: 0.4), outlineWidth: 2),
                                   frame: NormalizedRect(x: 0.08, y: 0.85, width: 0.84, height: 0.1), alignment: .leading, verticalAlignment: .top)),
        Theme(id: id(4), name: "Missing picture", background: .image(path: "/nonexistent/wf-ui005h-picture.png"),
              primary: TextBlock(style: TextStyle(fontName: "Helvetica Neue", fontSize: 72, color: .white, outlineWidth: 4),
                                 frame: NormalizedRect(x: 0.06, y: 0.3, width: 0.88, height: 0.4), alignment: .trailing, verticalAlignment: .center),
              secondary: TextBlock(style: TextStyle(fontName: "Courier", fontSize: 44, color: .white),
                                   frame: NormalizedRect(x: 0.06, y: 0.7, width: 0.88, height: 0.2), alignment: .trailing, verticalAlignment: .top)),
    ]

    /// The audience and broadcast pictures of one theme at 1280 x 720: the live slide, composed for each role.
    static func frames(of theme: Theme, compositor: Compositor, slide: SlideContent = sampleSlide) throws -> [RenderedFrame] {
        let state = live(slide)
        return try [ScreenRole.audience, .broadcast].map { role in
            let scene = SceneComposer.scene(for: role, state: state, theme: theme, look: .standard, props: [], clockText: nil)
            return try compositor.renderImage(scene: scene, width: 1280, height: 720)
        }
    }

    /// FNV-1a over the bytes: the same picture gives the same digest.
    static func digest(_ frame: RenderedFrame) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in frame.bgra { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// Registers the bundled Inter (Vendor/Inter) for this process, as the app does at launch, so the built-in looks are drawn in the
    /// font of the design. False when the file is missing.
    @discardableResult static func registerInter() -> Bool {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/Inter/InterVariable.ttf")
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        if let e = error?.takeRetainedValue(), CFErrorGetCode(e) == CTFontManagerError.alreadyRegistered.rawValue { return true }
        return false
    }
}
