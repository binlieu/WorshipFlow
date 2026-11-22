// UI-005h (OUT, KEY, STAGE): the built-in looks of the three screen roles, as docs/UI/mockups/07-output-looks.html draws them.
// Every number below was measured from the mockup with scripts/design-rects at 1920 x 1080 (see AI/reports/UI-005h-report.md); where the
// mockup writes a size in cqw, that is a percentage of the panel's content width (19.2 px for the audience and lower third panels, 17.664 px
// for the stage panel, which has 4 % padding). Sizes are points at the 1080-line reference height, which is a pixel at 1920 x 1080.
// The look before this slice is kept as the Classic themes (`Theme.classic`) and, for the stage, in the layouts operators made.
import Foundation

enum OutputLooks {
    /// The bundled Inter (variable), which the app registers at launch. A Mac that could not register it draws these looks in the system font.
    static let font = "InterVariable"

    static func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> ColorRGBA {
        ColorRGBA(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: a)
    }
    static let white = ColorRGBA.white
    static let yellow = rgb(0xff, 0xd1, 0x7b)           // `warning` #ffd17b, the second language and the message band
    static let muted = rgb(0x9f, 0xb2, 0xc7)            // `muted` #9fb2c7, the next line
    static let cyan = rgb(0x49, 0xd3, 0xc3)             // `cyan` #49d3c3, the timer
    static let onBrand = rgb(0x06, 0x21, 0x38)          // `on-brand` #062138, text on the band

    /// A design text style: Inter's text cut (optical size 14) with the single-storey a (cv11), as the pictures in docs/UI/screens show it.
    static func text(_ size: Double, _ weight: Int, _ color: ColorRGBA, lineHeight: Double, spacing: Double? = nil, shadow: TextShadow? = nil,
                     tabularFigures: Bool = false) -> TextStyle {
        TextStyle(fontName: font, fontSize: size, color: color, shadow: shadow, weight: weight, letterSpacing: spacing, lineHeight: lineHeight,
                  opticalSize: 14, fontFeatures: tabularFigures ? ["cv11", "tnum"] : ["cv11"])
    }

    /// A rectangle given in pixels of a 1920 x 1080 frame, as the fractions the model stores.
    static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> NormalizedRect {
        NormalizedRect(x: x / 1920, y: y / 1080, width: width / 1920, height: height / 1080)
    }

    // MARK: Audience: "Sanctuary, full-screen lyrics"

    /// radial-gradient(110% 100% at 80% 90%, #2d7d6c 0, #123b52 50%, #050f1c 100%)
    static let audienceGradient = GradientBackground(
        stops: [.init(position: 0, color: rgb(0x2d, 0x7d, 0x6c)), .init(position: 0.5, color: rgb(0x12, 0x3b, 0x52)),
                .init(position: 1, color: rgb(0x05, 0x0f, 0x1c))],
        centerX: 0.8, centerY: 0.9, radiusX: 1.1, radiusY: 1.0)

    /// text-shadow: 0 .3cqw 1.2cqw rgba(0, 0, 0, .6)
    static let lyricShadow = TextShadow(color: ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0.6), offsetX: 0, offsetY: 5.76, blur: 23.04)

    static func audienceTheme() -> Theme {
        // 6.2cqw / 600 / 1.2 and 4.1cqw / 500 / 1.3 (the second language is `lyric-secondary`). The two blocks are one group centred on the frame: the
        // primary's line boxes end at 547.87 px, the second language's start 3.4cqw (65.28 px) below, inside the 90 % title-safe width. The
        // primary's frame reaches up to the title-safe top (5 %) so a third line grows upwards inside it, and scripture slides are sized by it.
        let primaryBottom = 547.872 / 1080.0
        return Theme(
            id: Theme.fullScreenID, name: "Full screen", background: .media,
            primary: TextBlock(style: text(119.04, 600, white, lineHeight: 1.2, shadow: lyricShadow),
                               frame: NormalizedRect(x: 0.05, y: 0.05, width: 0.9, height: primaryBottom - 0.05),
                               alignment: .center, verticalAlignment: .bottom),
            secondary: TextBlock(style: text(78.72, 500, yellow, lineHeight: 1.3, shadow: lyricShadow),
                                 frame: NormalizedRect(x: 0.05, y: 613.152 / 1080.0, width: 0.9, height: 0.28),
                                 alignment: .center, verticalAlignment: .top),
            mediaFallback: audienceGradient)
    }

    // MARK: Broadcast: lower third

    static func lowerThirdTheme() -> Theme {
        // The plate is 88 % wide, 96 px (padding-bottom 5 % of the width) above the bottom, 19.2 px radius, padding 1.6cqw x 2.4cqw, fill
        // rgba(7, 19, 33, .86); the bar .6cqw wide, a 2cqw gap to the text, #42d9b8 to #4d99ed (white in the key: it is opaque).
        // Text 3.5cqw / 600 / 1.25 and 2.6cqw / 500 / 1.3, left-aligned. The plate stacks the lines itself: the frames only say where they start.
        let plate = TextPlate(x: 0.06, width: 0.88, bottomMargin: 96, fill: rgb(7, 19, 33, 0.86), cornerRadius: 19.2, paddingX: 46.08, paddingY: 30.72,
                              bar: AccentBar(width: 11.52, gap: 38.4, top: rgb(0x42, 0xd9, 0xb8), bottom: rgb(0x4d, 0x99, 0xed)))
        return Theme(
            id: Theme.lowerThirdID, name: "Lower third", background: .transparent,
            primary: TextBlock(style: text(67.2, 600, white, lineHeight: 1.25),
                               frame: rect(211.2, 804.4, 1548, 84), alignment: .leading, verticalAlignment: .top),
            secondary: TextBlock(style: text(49.92, 500, yellow, lineHeight: 1.3),
                                 frame: rect(211.2, 888.4, 1548, 64.9), alignment: .leading, verticalAlignment: .top),
            plate: plate)
    }

    // MARK: Stage: confidence monitor

    static let stageBackground = ColorRGBA(red: 0, green: 0, blue: 0)

    static func stageLayout() -> StageLayout {
        func id(_ n: Int) -> UUID { UUID(uuidString: "5A6E0002-0000-4000-8000-00000000000\(n)") ?? UUID() }
        // The stage panel has 4 % padding, so its cqw is 17.664 px: current 6.6cqw / 700 / 1.15, second language 3.6cqw / 600, NEXT 1.5cqw /
        // .08em tracking, next line 3.8cqw / 700 in `muted`, clock 4cqw, timer 6cqw in `cyan`, message band 2.6cqw / 700 on `warning`.
        let current = text(116.5824, 700, white, lineHeight: 1.15)
        let second = StageSecondLanguage(
            style: text(63.5904, 600, yellow, lineHeight: 1.3),
            // The mockup's own line box for this line is 16 px tall (the page's fixed line height) centred on y = 377.6, which puts a normal 1.3 line
            // at y = 336.27; the picture draws the line 12 px lower than that (ink 355 to 425 against 343 to 413), and the picture wins.
            frame: rect(76.8, 348.27, 1766.4, 82.67))
        let nextLabel = StageLabel(text: "NEXT", style: text(26.496, 700, muted, lineHeight: 1.3, spacing: 0.08),
                                   frame: rect(76.8, 796, 1766.4, 34.44))
        let clockFrame = rect(1843.2 - 400, 64.8, 400, 81.254)
        let timerFrame = rect(1843.2 - 600, 163.72, 600, 121.88)
        let band = StageMessageBand(
            plate: TextPlate(x: 0, width: 1, bottomMargin: 0, fill: yellow, cornerRadius: 0, paddingX: 76.8, paddingY: 17.664),
            style: text(45.9264, 700, onBrand, lineHeight: 1.3))
        return StageLayout(id: StageLayout.standardID, name: "Standard", background: stageBackground, elements: [
            StageElement(id: id(1), kind: .currentSlide, frame: rect(76.8, 76.8, 1766.4, 268.14), style: current, alignment: .leading,
                         showsSecondLanguage: true, secondLanguage: second),
            StageElement(id: id(2), kind: .nextSlide, frame: rect(76.8, 837.5, 1766.4, 80.55),
                         style: text(67.1232, 700, muted, lineHeight: 1.2),
                         alignment: .leading, showsSecondLanguage: false, label: nextLabel),
            StageElement(id: id(3), kind: .timeOfDay, frame: clockFrame,
                         style: text(70.656, 700, white, lineHeight: 1.15, tabularFigures: true), alignment: .trailing),
            StageElement(id: id(4), kind: .firstCountdown, frame: timerFrame,
                         style: text(105.984, 700, cyan, lineHeight: 1.15, tabularFigures: true), alignment: .trailing),
        ], messageBand: band)
    }
}
