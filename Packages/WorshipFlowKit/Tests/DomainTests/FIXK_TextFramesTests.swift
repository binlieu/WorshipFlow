// FIX-K item 3 (SLIDE): a slide may carry its own text frames for the first and second language. Stored in the theme's coordinate space (fractions of the
// frame), so they hold at every output size. A slide without them composes and encodes exactly as before.
import Testing
import Foundation
@testable import Domain

@Suite struct FIXK_TextFramesTests {
    let own = SlideTextFrames(primary: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25), secondary: nil)

    private func scene(_ content: SlideContent, role: ScreenRole = .audience, theme: Theme = .fullScreen) -> SceneDescription {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [content])))
        state.apply(.trigger(index: 0))
        return SceneComposer.scene(for: role, state: state, theme: theme, look: .standard, props: [])
    }

    @Test func aSlideWithoutTextFramesEncodesAsBeforeAndComposesWithTheThemesFrames() throws {
        let plain = SlideContent(primary: "Amazing grace", secondary: "Ân điển")
        #expect(plain.textFrames == nil)
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!json.contains("textFrames"))
        let layers = scene(plain).textLayers
        #expect(layers.map(\.frame) == [Theme.fullScreen.primary.frame, Theme.fullScreen.secondary?.frame].compactMap { $0 })
    }

    @Test func textFramesRoundTripAndEmptyOnesAreNotWritten() throws {
        var content = SlideContent(primary: "One", secondary: "Một")
        content.textFrames = own
        let back = try JSONDecoder().decode(SlideContent.self, from: JSONEncoder().encode(content))
        #expect(back == content && back.textFrames?.primary == own.primary && back.textFrames?.secondary == nil)
        // Both nil is the same as none.
        #expect(SlideTextFrames(primary: nil, secondary: nil).isEmpty)
        var empty = content
        empty.textFrames = SlideTextFrames()
        #expect(!String(decoding: try JSONEncoder().encode(empty), as: UTF8.self).contains("textFrames"))
    }

    @Test func theAudienceScreenUsesTheSlidesFrameAndTheThemesFrameForTheLanguageWithout() {
        var content = SlideContent(primary: "One", secondary: "Một")
        content.textFrames = own
        let layers = scene(content).textLayers
        #expect(layers.count == 2)
        #expect(layers[0].frame == own.primary)
        #expect(layers[1].frame == Theme.fullScreen.secondary?.frame)      // no override for the second language
        // The style, alignment and fit come from the theme: only the place moved.
        #expect(layers[0].style == Theme.fullScreen.primary.style && layers[0].alignment == Theme.fullScreen.primary.alignment)
        #expect(layers[0].fitFloor == (Theme.fullScreen.fitsText ? Theme.fitFloor : nil))
    }

    @Test func theSecondLanguageHasItsOwnFrameToo() {
        var content = SlideContent(primary: "One", secondary: "Một")
        let second = NormalizedRect(x: 0.2, y: 0.6, width: 0.6, height: 0.2)
        content.textFrames = SlideTextFrames(primary: nil, secondary: second)
        let layers = scene(content).textLayers
        #expect(layers[0].frame == Theme.fullScreen.primary.frame && layers[1].frame == second)
    }

    @Test func theBroadcastScreenKeepsItsOwnPlacement() {
        var content = SlideContent(primary: "One")
        content.textFrames = own
        let withOverride = scene(content, role: .broadcast, theme: .lowerThird)
        let without = scene(SlideContent(primary: "One"), role: .broadcast, theme: .lowerThird)
        #expect(withOverride.textLayers == without.textLayers)
    }

    @Test func aSlideWithoutFramesIsThePictureItWasBeforeForEveryBuiltInAndClassicTheme() {
        for theme in Theme.builtIn + Theme.classic {
            var withNil = SlideContent(primary: "One", secondary: "Two")
            withNil.textFrames = nil
            var withEmpty = withNil
            withEmpty.textFrames = SlideTextFrames()
            #expect(scene(withNil, theme: theme) == scene(withEmpty, theme: theme), "\(theme.name)")
            #expect(scene(withNil, theme: theme).textLayers.first?.frame == theme.primary.frame, "\(theme.name)")
        }
    }

    @Test func aCopyOfTheSlideContentCarriesTheFrames() {
        var content = SlideContent(primary: "One")
        content.textFrames = own
        let copy = content
        #expect(copy.textFrames == own)
    }
}
