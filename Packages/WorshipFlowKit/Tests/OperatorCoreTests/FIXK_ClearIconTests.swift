// FIX-K item 1 (owner: "icon clear picture active, expecting clean icon for video active"): the five clear icons are a pure function of what is live.
// The icon that lights is the one that takes that thing off, its glyph says what it clears, its tooltip names it. Selecting without sending lights nothing.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct FIXK_ClearIconTests {
    func state(_ live: ClearLiveState, _ icon: ClearIcon) -> ClearIconState { ClearIconState.state(for: icon, live: live) }
    func state(_ icon: ClearIcon) -> ClearIconState { state(ClearLiveState(), icon) }

    @Test func nothingLiveLightsNothingAndTheLayerIconsShowTheirPlainGlyph() {
        for icon in ClearIcon.allCases { #expect(state(icon).enabled == false, "\(icon)") }
        #expect(state(.background).glyph == .backgroundLayer && state(.foreground).glyph == .foregroundLayer)
        #expect(state(.background).tooltip == "Clear background: nothing live, ⌃⌥B")
    }

    @Test func aVideoOnTheBackgroundLayerLightsOnlyTheBackgroundIconWithAFilmGlyph() {
        let live = ClearLiveState(backgroundKind: .video, backgroundName: "Waves")
        let bg = state(live, .background)
        #expect(bg.enabled && bg.glyph == .film && bg.tooltip == "Clear background video: Waves, ⌃⌥B")
        #expect(!state(live, .foreground).enabled && !state(live, .lyric).enabled && !state(live, .music).enabled)
        #expect(state(live, .all).enabled)
        // It must not read as a picture.
        #expect(bg.glyph != .photo)
    }

    @Test func aPictureOnTheBackgroundLayerHasAPhotoGlyph() {
        let bg = state(ClearLiveState(backgroundKind: .image, backgroundName: "Cross"), .background)
        #expect(bg.enabled && bg.glyph == .photo && bg.tooltip == "Clear background picture: Cross, ⌃⌥B")
    }

    @Test func aClipOverTheWordsLightsOnlyTheForegroundIcon() {
        let live = ClearLiveState(foregroundKind: .video, foregroundName: "Announcements")
        let fg = state(live, .foreground)
        #expect(fg.enabled && fg.glyph == .film && fg.tooltip == "Clear foreground video: Announcements, ⌃⌥F")
        #expect(!state(live, .background).enabled)
        let still = state(ClearLiveState(foregroundKind: .image, foregroundName: "Welcome"), .foreground)
        #expect(still.enabled && still.glyph == .photo && still.tooltip == "Clear foreground picture: Welcome, ⌃⌥F")
    }

    @Test func wordsAndMusicLightTheirOwnIconOnly() {
        let words = ClearLiveState(hasLiveWords: true)
        #expect(state(words, .lyric).enabled && state(words, .lyric).tooltip == "Clear lyric, esc" && state(words, .lyric).glyph == .words)
        #expect(!state(words, .background).enabled && !state(words, .foreground).enabled && !state(words, .music).enabled)
        let music = ClearLiveState(musicName: "Hymn")
        #expect(state(music, .music).enabled && state(music, .music).glyph == .music && state(music, .music).tooltip == "Clear music: Hymn, ⌃⌥M")
        #expect(!state(music, .lyric).enabled)
    }

    @Test func clearAllIsEnabledWhenAnyOtherIconIsAndHasItsOwnGlyph() {
        for live in [ClearLiveState(hasLiveWords: true), ClearLiveState(backgroundKind: .video), ClearLiveState(foregroundKind: .video), ClearLiveState(musicName: "x")] {
            #expect(state(live, .all).enabled && state(live, .all).glyph == .all && state(live, .all).tooltip == "Clear all, ⇧ esc")
        }
        #expect(!state(.all).enabled)
    }

    @Test func aMissingNameStillGivesAUsableTooltip() {
        #expect(state(ClearLiveState(backgroundKind: .video), .background).tooltip == "Clear background video, ⌃⌥B")
    }

    @Test func everyLayerAndKindCombinationIsAnswered() {
        for kind in [MediaKind.video, .image] {
            for icon in [ClearIcon.background, .foreground] {
                let live = icon == .background ? ClearLiveState(backgroundKind: kind, backgroundName: "N") : ClearLiveState(foregroundKind: kind, foregroundName: "N")
                let s = state(live, icon)
                #expect(s.enabled && s.glyph == (kind == .video ? .film : .photo) && s.tooltip.contains(kind == .video ? "video" : "picture"))
            }
        }
    }
}
