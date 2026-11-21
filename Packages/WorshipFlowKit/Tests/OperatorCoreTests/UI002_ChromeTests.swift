// UI-002 Part 1: header labels collapse by width, the Clear split control, thumbnails with a media background.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct UI002_HeaderLabelTests {
    @Test func labelsShowWhenTheHeaderIsWideEnough() {
        #expect(HeaderChrome.showsLabels(availableWidth: 1000, labelledWidth: 700))
        #expect(HeaderChrome.showsLabels(availableWidth: 700, labelledWidth: 700))
    }
    @Test func labelsCollapseToIconsWhenTooNarrow() {
        #expect(!HeaderChrome.showsLabels(availableWidth: 699, labelledWidth: 700))
        #expect(!HeaderChrome.showsLabels(availableWidth: 0, labelledWidth: 700))
    }
    @Test func everyHeaderControlHasATooltipAndAnAccessibilityLabelEitherWay() {
        for control in HeaderChrome.Control.allCases {
            #expect(!control.title.isEmpty)
            #expect(!control.tooltip.isEmpty)
            #expect(!control.accessibilityLabel.isEmpty)
        }
        #expect(HeaderChrome.Control.quickEdit.keyHint == "⌘E")
        #expect(HeaderChrome.Control.addSlide.keyHint == nil)
        #expect(HeaderChrome.Control.reflow.title == "Reflow…")
    }
}

@Suite struct UI002_ClearControlTests {
    @Test func clickClearsWordsAndMenuOffersClearAll() {
        #expect(ClearControl.primary == .clearWords)
        #expect(ClearControl.menu == [.clearAll])
        #expect(ClearControl.Action.clearWords.title == "Clear")
        #expect(ClearControl.Action.clearAll.title == "Clear all")
        #expect(ClearControl.Action.clearAll.detail.contains("clip"))
    }
}

@Suite struct UI002_ThumbnailPolicyTests {
    private func scene(media: Bool) -> SceneDescription {
        var s = SceneDescription(backgroundColor: .black, showsVideo: media, textLayers: [])
        if media { s.backgroundMedia = .video(UUID()) }
        return s
    }
    @Test func aSceneWithoutMediaNeedsNoFramesAndIsCached() {
        let p = ThumbnailPolicy(scene: scene(media: false))
        #expect(!p.wantsFrames && p.cacheable)
    }
    @Test func aSceneWithMediaAsksForOneStillFrameAndIsNotCached() {
        let p = ThumbnailPolicy(scene: scene(media: true))
        #expect(p.wantsFrames && !p.cacheable && !p.animates)
    }
}

@Suite struct UI002_MirrorNoteTests {
    @Test func removingAMirrorRemovesItsNoteAndKeepsTheOthersAligned() {
        var p = ScreenProfile(name: "S", role: .audience, destination: .window, mirrors: [.window, .window])
        p.setConnectedNote("primary", mirror: nil)
        p.setConnectedNote("first", mirror: 0)
        p.setConnectedNote("second", mirror: 1)
        let q = ScreenEditing.removingMirror(p, at: 0)
        #expect(q.mirrors.count == 1 && q.connectedNote(mirror: nil) == "primary" && q.connectedNote(mirror: 0) == "second")
    }
}

@Suite struct UI002_MediaBinCategoryTests {
    @Test func categoriesCountEachKindAndKeepAudioSeparate() {
        let entries = MediaBinCategories.entries(kinds: [.video, .video, .image, .audio, .audio, .audio])
        #expect(entries.map(\.title) == ["All media", "Videos", "Pictures", "Sound"])
        #expect(entries.map(\.count) == [6, 2, 1, 3])
        #expect(entries.map(\.kind) == [nil, .video, .image, .audio])
        #expect(entries.map(\.isAudio) == [false, false, false, true])
    }
    @Test func anEmptyBinHasZeroCounts() {
        #expect(MediaBinCategories.entries(kinds: []).map(\.count) == [0, 0, 0, 0])
    }
    @Test func theHeaderNamesTheSelectedCategory() {
        #expect(MediaBinCategories.title(for: nil) == "All media")
        #expect(MediaBinCategories.title(for: .image) == "Pictures")
    }
}
