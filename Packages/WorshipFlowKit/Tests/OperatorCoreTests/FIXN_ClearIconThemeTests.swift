// FIX-N item 4 (FIX-K item 1): a theme whose own background is a video or a picture is something Clear background removes, so the background icon is
// enabled and shows its kind, and its tooltip names it. A bin choice or the slide's own background is still named first.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct FIXN_ClearIconThemeTests {
    func state(_ live: ClearLiveState, _ icon: ClearIcon) -> ClearIconState { ClearIconState.state(for: icon, live: live) }

    @Test func aThemeVideoLightsTheBackgroundIconWithAFilmGlyphAndNamesItInTheTooltip() {
        let live = ClearLiveState(themeBackgroundKind: .video)
        let bg = state(live, .background)
        #expect(bg.enabled && bg.glyph == .film && bg.tooltip == "Clear background: theme video, ⌃⌥B")
        #expect(!state(live, .foreground).enabled && !state(live, .lyric).enabled && !state(live, .music).enabled)
        #expect(state(live, .all).enabled)
    }

    @Test func aThemePictureLightsItWithAPhotoGlyph() {
        let bg = state(ClearLiveState(themeBackgroundKind: .image), .background)
        #expect(bg.enabled && bg.glyph == .photo && bg.tooltip == "Clear background: theme picture, ⌃⌥B")
    }

    @Test func aBinChoiceOrTheSlidesOwnBackgroundIsNamedBeforeTheTheme() {
        let live = ClearLiveState(backgroundKind: .video, backgroundName: "Waves", themeBackgroundKind: .image)
        let bg = state(live, .background)
        #expect(bg.enabled && bg.glyph == .film && bg.tooltip == "Clear background video: Waves, ⌃⌥B")
    }

    @Test func noThemeBackgroundAndNothingElseStaysOff() {
        #expect(!state(ClearLiveState(), .background).enabled)
        #expect(state(ClearLiveState(), .background).tooltip == "Clear background: nothing live, ⌃⌥B")
        #expect(!state(ClearLiveState(), .all).enabled)
    }

    @Test func whichThemeBackgroundsCountAsAVideoOrAPicture() {
        #expect(ClearIconRule.themeBackgroundKind(.media) == .video)
        #expect(ClearIconRule.themeBackgroundKind(.image(path: "/x/cross.png")) == .image)
        #expect(ClearIconRule.themeBackgroundKind(.color(.black)) == nil)
        #expect(ClearIconRule.themeBackgroundKind(.transparent) == nil)
    }
}
