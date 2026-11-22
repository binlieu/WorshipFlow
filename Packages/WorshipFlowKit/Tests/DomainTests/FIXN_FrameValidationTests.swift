// FIX-N item 2 (FIX-K): a slide's own text frame is validated when it is read, the same way the editor clamps what it writes. A frame with zero or
// negative size, a non-finite value, or one wholly outside the canvas is treated as no override: the slide then draws the theme's position.
import Testing
import Foundation
@testable import Domain

@Suite struct FIXN_FrameValidationTests {
    static let hostile: [(String, String)] = [
        ("zero width", #"{"x":0.1,"y":0.1,"width":0,"height":0.3}"#),
        ("zero height", #"{"x":0.1,"y":0.1,"width":0.3,"height":0}"#),
        ("negative width", #"{"x":0.5,"y":0.1,"width":-0.3,"height":0.3}"#),
        ("negative height", #"{"x":0.1,"y":0.5,"width":0.3,"height":-0.3}"#),
        ("wholly right of the canvas", #"{"x":1.5,"y":0.1,"width":0.3,"height":0.3}"#),
        ("wholly below the canvas", #"{"x":0.1,"y":1.0,"width":0.3,"height":0.3}"#),
        ("wholly left of the canvas", #"{"x":-0.9,"y":0.1,"width":0.5,"height":0.3}"#),
        ("wholly above the canvas", #"{"x":0.1,"y":-0.4,"width":0.3,"height":0.4}"#),
        ("a hundred screens away", #"{"x":1e300,"y":1e300,"width":1e300,"height":1e300}"#),
        ("all zero", #"{"x":0,"y":0,"width":0,"height":0}"#),
    ]

    private func content(_ primary: String?, _ secondary: String? = nil) throws -> SlideContent {
        var parts: [String] = []
        if let primary { parts.append("\"primary\":\(primary)") }
        if let secondary { parts.append("\"secondary\":\(secondary)") }
        let json = "{\"primary\":\"One\",\"secondary\":\"Một\",\"textFrames\":{\(parts.joined(separator: ","))}}"
        return try JSONDecoder().decode(SlideContent.self, from: Data(json.utf8))
    }

    private func scene(_ content: SlideContent, theme: Theme = .fullScreen) -> SceneDescription {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [content])))
        state.apply(.trigger(index: 0))
        return SceneComposer.scene(for: .audience, state: state, theme: theme, look: .standard, props: [])
    }

    @Test func aHostileFrameDecodesAsNoOverride() throws {
        for (name, frame) in Self.hostile {
            let decoded = try content(frame)
            #expect(decoded.textFrames == nil, "\(name)")
        }
    }

    @Test func aBadLanguageIsDroppedAndTheGoodOneKept() throws {
        let good = #"{"x":0.1,"y":0.2,"width":0.5,"height":0.25}"#
        let decoded = try content(Self.hostile[0].1, good)
        #expect(decoded.textFrames?.primary == nil)
        #expect(decoded.textFrames?.secondary == NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25))
    }

    @Test func aGoodFrameIsKeptExactly() throws {
        let decoded = try content(#"{"x":0.1,"y":0.2,"width":0.5,"height":0.25}"#)
        #expect(decoded.textFrames?.primary == NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25))
    }

    @Test func aFrameHangingOverTheEdgeIsClampedLikeTheEditorDoes() throws {
        let decoded = try content(#"{"x":0.8,"y":0.9,"width":0.5,"height":0.4}"#)
        let frame = try #require(decoded.textFrames?.primary)
        #expect(frame.width == 0.5 && frame.height == 0.4)
        #expect(abs(frame.x - 0.5) < 1e-12 && abs(frame.y - 0.6) < 1e-12)
        #expect(frame.x >= 0 && frame.y >= 0 && frame.x + frame.width <= 1 + 1e-12 && frame.y + frame.height <= 1 + 1e-12)
        // A frame bigger than the canvas is cut down to it.
        let big = try #require(try content(#"{"x":-3,"y":-3,"width":50,"height":50}"#).textFrames?.primary)
        #expect(big == NormalizedRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func aTinyFrameIsRaisedToTheMinimumSizeTheEditorKeeps() throws {
        let frame = try #require(try content(#"{"x":0.1,"y":0.1,"width":0.001,"height":0.001}"#).textFrames?.primary)
        #expect(frame.width == SlideObject.minimumSize && frame.height == SlideObject.minimumSize)
    }

    @Test func aBadFrameDrawsTheThemesPositionWhateverHowItGotIntoTheSlide() {
        let nan = Double.nan
        let bad: [NormalizedRect] = [
            NormalizedRect(x: 0.1, y: 0.1, width: 0, height: 0.3), NormalizedRect(x: 0.1, y: 0.1, width: -0.2, height: 0.3),
            NormalizedRect(x: nan, y: 0.1, width: 0.3, height: 0.3), NormalizedRect(x: 0.1, y: 0.1, width: .infinity, height: 0.3),
            NormalizedRect(x: 2, y: 2, width: 0.3, height: 0.3), NormalizedRect(x: 0.1, y: -5, width: 0.3, height: 0.3),
        ]
        let themeFrames = [Theme.fullScreen.primary.frame, Theme.fullScreen.secondary?.frame].compactMap { $0 }
        for frame in bad {
            var slide = SlideContent(primary: "One", secondary: "Một")
            slide.textFrames = SlideTextFrames(primary: frame, secondary: frame)
            #expect(scene(slide).textLayers.map(\.frame) == themeFrames, "\(frame)")
        }
    }

    @Test func aGoodOwnFrameStillMovesTheWords() {
        var slide = SlideContent(primary: "One", secondary: "Một")
        let own = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25)
        slide.textFrames = SlideTextFrames(primary: own, secondary: nil)
        let layers = scene(slide).textLayers
        #expect(layers.first?.frame == own)
        #expect(layers.dropFirst().first?.frame == Theme.fullScreen.secondary?.frame)
    }
}
