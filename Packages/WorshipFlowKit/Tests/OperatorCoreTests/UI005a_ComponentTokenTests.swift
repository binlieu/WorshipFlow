// UI-005a: the shared components take their numbers from named tokens. The radii in DesignTokens.swift equal design-tokens.json,
// and the values ui.css has but the token file lacks (the segmented track 7, a segment 5, the toggle 30 x 18, the scrubber 5 / 13,
// the thumbnail rings 2 / 3 at a 2 pt offset) equal the mockup's CSS, so neither side can drift silently.
import Testing
import Foundation

@Suite struct UI005a_ComponentTokenTests {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: DesignTokenParityTests.root.appendingPathComponent(path), encoding: .utf8)
    }

    @Test func radiiInTheAppEqualTheTokenFile() throws {
        let json = try read("docs/UI/design-tokens.json")
        let swift = try read("App/Sources/DesignTokens.swift")
        for (name, value) in [("xs", 3), ("sm", 4), ("md", 6), ("lg", 8), ("xl", 10)] {
            #expect(json.contains("\"radius-\(name)\"") && json.contains("\"\(value)px\""), "token file has radius-\(name)")
            #expect(swift.contains("\(name): CGFloat = \(value)"), "app has Radius.\(name) = \(value)")
        }
    }

    @Test func valuesTheTokenFileLacksEqualTheMockupCSS() throws {
        let css = try read("docs/UI/mockups/ui.css")
        let swift = try read("App/Sources/DesignTokens.swift")
        #expect(css.contains(".seg{display:inline-flex;background:var(--surface-2);border:1px solid var(--border);border-radius:7px;padding:2px"))
        #expect(css.contains("border-radius:5px;color:var(--muted)"))
        #expect(swift.contains("track: CGFloat = 7") && swift.contains("segment: CGFloat = 5"))
        #expect(css.contains(".tgl{width:30px;height:18px"))
        #expect(swift.contains("toggleWidth: CGFloat = 30") && swift.contains("toggleHeight: CGFloat = 18") && swift.contains("checkboxSize: CGFloat = 14"))
        #expect(css.contains(".chk{width:14px;height:14px"))
        #expect(css.contains(".thumb.sel{outline:2px solid var(--sel);outline-offset:2px}") && css.contains(".thumb.live{outline:3px solid var(--live-fill);outline-offset:2px}"))
        #expect(swift.contains("thumbRingPreview: CGFloat = 2") && swift.contains("thumbRingLive: CGFloat = 3") && swift.contains("thumbRingOffset: CGFloat = 2"))
        let show = try read("docs/UI/mockups/01-operator-show.html")
        #expect(show.contains(".scrub{height:5px") && show.contains("width:13px;height:13px"))
        #expect(swift.contains("scrubTrack: CGFloat = 5") && swift.contains("scrubThumb: CGFloat = 13"))
        #expect(css.contains(".tm{display:flex;align-items:center;gap:6px;height:28px") && swift.contains("timerCapsuleHeight: CGFloat = 28"))
    }
}
