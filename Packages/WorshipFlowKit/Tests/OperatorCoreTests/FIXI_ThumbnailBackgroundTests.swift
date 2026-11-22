// FIX-I item 5, owner: "the slide thumbnail should have background so operator will know what background will be live in that slide".
// A slide thumbnail draws the background the slide will have when it goes live with no bin override: its own, else the presentation's or the
// theme's. A video background is one still frame (cached by file and modification date, no player, no open decoder) with a film mark; a
// missing file shows the missing-media state. These tests cover the decision and the cache; the drawing is the one Compositor.
import Foundation
import Testing
import Domain
@testable import OperatorCore

@Suite struct FIXI_ThumbnailBackgroundTests {
    static let video = MediaSelection(assetID: UUID(), kind: .video, duration: 20)
    static let picture = MediaSelection(assetID: UUID(), kind: .image, duration: nil)

    private func slide(_ background: MediaSelection? = nil) -> SlideContent {
        var content = SlideContent(primary: "Words")
        content.background = background
        return content
    }

    // MARK: what a thumbnail draws

    @Test func aSlideWithItsOwnBackgroundDrawsIt() {
        let resolved = ThumbnailBackground.resolve(slide: slide(Self.picture), theme: .fullScreen, themeIsThePresentations: false, available: [Self.picture.assetID])
        #expect(resolved == .slideOwn(Self.picture))
        #expect(resolved.stillToLoad == Self.picture && !resolved.showsFilmMark && !resolved.isMissing)
    }

    @Test func aVideoBackgroundIsOneStillWithAFilmMark() {
        let resolved = ThumbnailBackground.resolve(slide: slide(Self.video), theme: .fullScreen, themeIsThePresentations: false, available: [Self.video.assetID])
        #expect(resolved == .slideOwn(Self.video))
        #expect(resolved.stillToLoad == Self.video && resolved.showsFilmMark)
    }

    @Test func aSlideWithoutOneDrawsThePresentationsThemeBackground() {
        var theme = Theme.fullScreen
        theme.background = .color(ColorRGBA(red: 0.1, green: 0.2, blue: 0.6, alpha: 1))
        let resolved = ThumbnailBackground.resolve(slide: slide(), theme: theme, themeIsThePresentations: true, available: [])
        #expect(resolved == .theme(theme.background, fromPresentation: true))
        #expect(resolved.stillToLoad == nil && !resolved.showsFilmMark && !resolved.isMissing)
    }

    @Test func aSlideWithoutOneDrawsTheDefaultThemeBackgroundWhenThePresentationHasNone() {
        let resolved = ThumbnailBackground.resolve(slide: slide(), theme: .fullScreen, themeIsThePresentations: false, available: [])
        #expect(resolved == .theme(Theme.fullScreen.background, fromPresentation: false))
    }

    @Test func aMissingFileDrawsTheMissingMediaStateAndLoadsNothing() {
        let resolved = ThumbnailBackground.resolve(slide: slide(Self.video), theme: .fullScreen, themeIsThePresentations: false, available: [])
        #expect(resolved == .slideOwnMissing(Self.video))
        #expect(resolved.isMissing && resolved.stillToLoad == nil && !resolved.showsFilmMark, "the warning mark stands in for the film mark")
    }

    @Test func whenTheBinsItemsAreNotKnownYetTheOwnBackgroundIsTakenAsPresent() {
        let resolved = ThumbnailBackground.resolve(slide: slide(Self.picture), theme: .fullScreen, themeIsThePresentations: false, available: nil)
        #expect(resolved == .slideOwn(Self.picture))
    }

    // MARK: a bin override never changes a thumbnail, but it is what the Live monitor shows

    @Test func theThumbnailSceneIgnoresALiveBinOverrideAndKeepsTheSlidesOwnBackground() {
        let override = MediaSelection(assetID: UUID(), kind: .video, duration: 5)
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [slide(Self.picture)])))
        state.apply(.trigger(index: 0))
        var live = MediaLayers()
        live.setBackground(override, at: 0)
        let thumbnail = SceneComposer.scene(for: .audience, state: state, theme: .fullScreen, look: .standard, props: [],
                                            media: LiveMedia.preview(slide: slide(Self.picture), at: 0))
        let monitor = SceneComposer.scene(for: .audience, state: state, theme: .fullScreen, look: .standard, props: [],
                                          media: LiveMedia.effective(override: live, slide: state.liveSlideAtPlace, at: 0))
        #expect(thumbnail.backgroundMedia == .image(Self.picture.assetID), "what the slide will have with no bin override")
        #expect(monitor.backgroundMedia == .video(override.assetID), "the Live monitor shows what is really live")
    }

    // MARK: the still cache

    private func key(_ path: String, _ seconds: TimeInterval, size: Int64 = 100) -> StillCacheKey {
        StillCacheKey(path: path, modified: Date(timeIntervalSince1970: seconds), size: size)
    }

    @Test func aStillIsReusedForTheSameFileAndModificationDate() {
        var cache = StillCache<String>(limit: 4)
        cache.insert("frame", for: key("/m/a.mov", 10))
        #expect(cache.value(for: key("/m/a.mov", 10)) == "frame")
    }

    @Test func aChangedFileIsNotServedFromTheOldStill() {
        var cache = StillCache<String>(limit: 4)
        cache.insert("old", for: key("/m/a.mov", 10))
        #expect(cache.value(for: key("/m/a.mov", 11)) == nil, "the modification date changed")
        #expect(cache.value(for: key("/m/a.mov", 10, size: 200)) == nil, "the size changed")
        #expect(cache.value(for: key("/m/b.mov", 10)) == nil)
    }

    @Test func theCacheIsBoundedAndDropsTheLeastRecentlyUsed() {
        var cache = StillCache<Int>(limit: 3)
        for n in 0..<3 { cache.insert(n, for: key("/m/\(n).mov", 1)) }
        _ = cache.value(for: key("/m/0.mov", 1))                // 0 is now the newest; 1 is the oldest
        cache.insert(3, for: key("/m/3.mov", 1))
        #expect(cache.count == 3)
        #expect(cache.value(for: key("/m/1.mov", 1)) == nil)
        #expect(cache.value(for: key("/m/0.mov", 1)) == 0 && cache.value(for: key("/m/2.mov", 1)) == 2 && cache.value(for: key("/m/3.mov", 1)) == 3)
    }

    @Test func twoHundredSlidesOfOneBackgroundNeedOneStill() {
        var cache = StillCache<String>(limit: 24)
        var loads = 0
        for _ in 0..<200 {
            let k = key("/m/loop.mov", 5)
            if cache.value(for: k) == nil { loads += 1; cache.insert("frame", for: k) }
        }
        #expect(loads == 1 && cache.count == 1)
    }
}
