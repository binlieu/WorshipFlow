// UI-003 Part 1: the pure decisions behind the revised Show mode (slide grid columns, media dock, inspector tabs,
// Quick edit wording, Look row, monitors, layer presence). The views only draw what these return.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct UI003_SlideGridTests {
    @Test func fiveAcrossAtTheDesignWindowSize() {
        // 1440 pt window, 256 pt sidebar, 372 pt inspector: the centre column is 812 pt wide.
        #expect(SlideGridLayout.columnCount(width: 812) == 5)
    }
    @Test func moreColumnsWhenWiderAndFewerWhenNarrower() {
        #expect(SlideGridLayout.columnCount(width: 932) == 6)
        #expect(SlideGridLayout.columnCount(width: 460) == 2)
        var last = 0
        for w in stride(from: 200.0, through: 1600.0, by: 25.0) {
            let n = SlideGridLayout.columnCount(width: w)
            #expect(n >= last && n >= 1)
            last = n
        }
    }
    @Test func neverZeroColumns() {
        #expect(SlideGridLayout.columnCount(width: 0) == 1)
        #expect(SlideGridLayout.columnCount(width: -50) == 1)
        #expect(SlideGridLayout.columnCount(width: .nan) == 1)
    }
}

@Suite struct UI003_MediaDockTests {
    func asset(_ kind: MediaKind, _ name: String = "x") -> MediaAsset { MediaAsset(name: name, kind: kind, path: "/m/\(name)") }

    @Test func fourTabsInTheDesignOrder() {
        #expect(MediaDockTab.allCases.map(\.title) == ["Backgrounds", "Videos", "Images", "Audio"])
    }
    @Test func eachTabListsItsKinds() {
        let all = [asset(.video, "v"), asset(.image, "i"), asset(.audio, "a")]
        #expect(MediaDock.assets(all, tab: .videos).map(\.name) == ["v"])
        #expect(MediaDock.assets(all, tab: .images).map(\.name) == ["i"])
        #expect(MediaDock.assets(all, tab: .audio).map(\.name) == ["a"])
        // Backgrounds: anything that can sit behind the words (a picture or a video), never sound.
        #expect(MediaDock.assets(all, tab: .backgrounds).map(\.name) == ["v", "i"])
    }
    @Test func aClickFollowsTheLayerChoice() {
        let v = asset(.video), i = asset(.image)
        #expect(MediaDock.action(for: v, layer: .background) == .setBackground(v.id))
        #expect(MediaDock.action(for: v, layer: .foreground) == .playForeground(v.id))
        #expect(MediaDock.action(for: i, layer: .background) == .setBackground(i.id))
        #expect(MediaDock.action(for: i, layer: .foreground) == .playForeground(i.id))
    }
    @Test func soundAlwaysPlaysAsACueWhateverTheLayerChoice() {
        let a = asset(.audio)
        #expect(MediaDock.action(for: a, layer: .background) == .playAudio(a.id))
        #expect(MediaDock.action(for: a, layer: .foreground) == .playAudio(a.id))
        #expect(MediaDock.showsLayerChoice(on: .audio) == false)
        #expect(MediaDock.showsLayerChoice(on: .videos) && MediaDock.showsLayerChoice(on: .backgrounds) && MediaDock.showsLayerChoice(on: .images))
    }
    @Test func heightIsKeptBetweenAMinimumAndHalfTheColumn() {
        #expect(MediaDock.clampedHeight(10, available: 800) == MediaDock.minimumHeight)
        #expect(MediaDock.clampedHeight(190, available: 800) == 190)
        #expect(MediaDock.clampedHeight(900, available: 800) == 400)
        #expect(MediaDock.clampedHeight(300, available: 200) == MediaDock.minimumHeight)     // a tiny window still gets the minimum
        #expect(MediaDock.clampedHeight(.nan, available: 800) == MediaDock.defaultHeight)
    }
}

@Suite struct UI003_InspectorTabsTests {
    @Test func threeTabsUntilQuickEditOpens() {
        var tabs = InspectorTabs()
        #expect(tabs.visible == [.props, .cues, .audio] && tabs.selected == .props)
        let opened = tabs.openQuickEdit(hasSelectedSlide: true)
        #expect(opened)
        #expect(tabs.visible == [.props, .cues, .audio, .quickEdit] && tabs.selected == .quickEdit)
    }
    @Test func quickEditNeedsASlideToEdit() {
        var tabs = InspectorTabs()
        let opened = tabs.openQuickEdit(hasSelectedSlide: false)
        #expect(!opened)
        #expect(tabs.visible == [.props, .cues, .audio] && tabs.selected == .props)
    }
    @Test func doneRemovesTheTabAndReturnsToWhereTheOperatorWas() {
        var tabs = InspectorTabs()
        tabs.select(.audio)
        _ = tabs.openQuickEdit(hasSelectedSlide: true)
        tabs.closeQuickEdit()
        #expect(tabs.visible == [.props, .cues, .audio] && tabs.selected == .audio)
    }
    @Test func otherTabsCanBeChosenWhileQuickEditStaysOpen() {
        var tabs = InspectorTabs()
        _ = tabs.openQuickEdit(hasSelectedSlide: true)
        tabs.select(.cues)
        #expect(tabs.selected == .cues && tabs.visible.contains(.quickEdit))
        _ = tabs.openQuickEdit(hasSelectedSlide: true)       // Command-E again brings it back
        #expect(tabs.selected == .quickEdit)
    }
    @Test func theQuickEditTabCannotBeChosenWhileClosedAndGoesWhenTheSlideDoes() {
        var tabs = InspectorTabs()
        tabs.select(.quickEdit)
        #expect(tabs.selected == .props)
        _ = tabs.openQuickEdit(hasSelectedSlide: true)
        tabs.selectedSlideChanged(hasSelectedSlide: false)
        #expect(tabs.visible == [.props, .cues, .audio] && tabs.selected == .props)
    }
}

@Suite struct UI003_QuickEditWordingTests {
    @Test func theTwoMeaningsStayApartInWordsAndKeys() {
        #expect(QuickEditLabels.previewShortcut == "⌘E")
        #expect(QuickEditLabels.liveShortcut == "⌥⌘E")
        #expect(QuickEditLabels.previewShortcut != QuickEditLabels.liveShortcut)
        #expect(QuickEditLabels.previewChip == "Preview only")
        #expect(QuickEditLabels.liveTitle.lowercased().contains("live"))
        #expect(!QuickEditLabels.previewTitle.lowercased().contains("live"))
        #expect(QuickEditLabels.liveWarning.lowercased().contains("audience sees"))
        #expect(QuickEditLabels.previewNote.lowercased().contains("not the screens") || QuickEditLabels.previewNote.lowercased().contains("preview"))
    }
    @Test func theHeaderButtonIsTheSelectedSlideEditNotTheLiveOne() {
        #expect(HeaderChrome.Control.quickEdit.keyHint == "⌘E")
        #expect(!HeaderChrome.Control.quickEdit.tooltip.contains("reaches the live screens"))
        #expect(HeaderChrome.Control.quickEdit.tooltip.lowercased().contains("preview"))
    }
}

@Suite struct UI003_LookRowTests {
    func looks(_ names: [String]) -> [Look] { names.map { Look(id: UUID(), name: $0) } }

    @Test func fewLooksAllShowAndNothingOverflows() {
        let l = looks(["Full", "Notes"])
        let s = LookRow.split(l, selected: l[0].id, capacity: 4)
        #expect(s.visible == l && s.overflow.isEmpty)
    }
    @Test func theRestGoToTheMenuInOrder() {
        let l = looks(["A", "B", "C", "D", "E", "F"])
        let s = LookRow.split(l, selected: l[0].id, capacity: 4)
        #expect(s.visible.map(\.name) == ["A", "B", "C", "D"] && s.overflow.map(\.name) == ["E", "F"])
    }
    @Test func theSelectedLookIsAlwaysOnTheRow() {
        let l = looks(["A", "B", "C", "D", "E", "F"])
        let s = LookRow.split(l, selected: l[5].id, capacity: 4)
        #expect(s.visible.map(\.name) == ["A", "B", "C", "F"])
        #expect(s.overflow.map(\.name) == ["D", "E"])
        #expect(Set(s.visible + s.overflow) == Set(l))
    }
    @Test func shortNamesAllFitAndLongOnesFewer() {
        let short = looks(["Full", "Notes", "Lower 3rd", "BG only"])
        #expect(LookRow.capacity(for: short, availableWidth: 290) == 4)
        let long = looks(["Standard", "Sunday morning", "Lower third only", "Sermon"])
        #expect(LookRow.capacity(for: long, availableWidth: 270) == 2)
        #expect(LookRow.capacity(for: long, availableWidth: 10) == 1)
        #expect(LookRow.capacity(for: [], availableWidth: 270) == 1)
    }
    @Test func noLooksMeansAnEmptyRow() {
        let s = LookRow.split([], selected: nil, capacity: 4)
        #expect(s.visible.isEmpty && s.overflow.isEmpty)
    }
}

@Suite struct UI003_MonitorsTests {
    func profile(_ name: String, _ role: ScreenRole, enabled: Bool = true) -> ScreenProfile {
        ScreenProfile(name: name, role: role, destination: .window, isEnabled: enabled)
    }
    @Test func liveIsTheFirstEnabledAudienceScreen() {
        let a1 = profile("Off", .audience, enabled: false), a2 = profile("Sanctuary", .audience)
        #expect(ShowMonitors.live([a1, a2])?.name == "Sanctuary")
        #expect(ShowMonitors.live([a1])?.name == "Off")           // none enabled: still names the audience screen
        #expect(ShowMonitors.live([profile("S", .stage)]) == nil)
    }
    @Test func everyOtherEnabledScreenFollowsStageThenBroadcastThenOtherAudience() {
        let all = [profile("Sanctuary", .audience), profile("Lobby", .audience), profile("Stream", .broadcast),
                   profile("Band", .stage), profile("Spare", .stage, enabled: false)]
        #expect(ShowMonitors.others(all).map(\.name) == ["Band", "Stream", "Lobby"])
    }
}

@Suite struct UI003_LayerPresenceTests {
    func screen(_ role: ScreenRole, _ layers: Set<LayerKind> = Set(LayerKind.allCases), enabled: Bool = true, media: Bool = true) -> ScreenLayerInput {
        ScreenLayerInput(role: role, isEnabled: enabled, visibleLayers: layers, backgroundIsMedia: media)
    }
    @Test func propsShowOnTheRolesWhoseScreensShowThePropsLayer() {
        let s = [screen(.audience), screen(.broadcast, [.slide, .props]), screen(.stage)]
        #expect(LayerPresence.roles(showing: .props, screens: s) == [.audience, .broadcast])
    }
    @Test func aScreenThatHidesTheLayerOrIsOffIsLeftOut() {
        let s = [screen(.audience, [.slide]), screen(.broadcast, enabled: false)]
        #expect(LayerPresence.roles(showing: .props, screens: s).isEmpty)
    }
    @Test func stageScreensNeverShowPropsOrMedia() {
        #expect(LayerPresence.roles(showing: .props, screens: [screen(.stage)]).isEmpty)
        #expect(LayerPresence.backgroundMediaRoles(screens: [screen(.stage)]).isEmpty)
    }
    @Test func aBackgroundVideoIsOnlyOnScreensWhoseThemeUsesMotionBackgrounds() {
        let s = [screen(.audience, media: true), screen(.broadcast, media: false)]
        #expect(LayerPresence.backgroundMediaRoles(screens: s) == [.audience])
        let hidden = [screen(.audience, [.slide, .props], media: true)]
        #expect(LayerPresence.backgroundMediaRoles(screens: hidden).isEmpty)
    }
    @Test func aClipOverTheSlideFollowsTheSlideLayer() {
        let s = [screen(.audience), screen(.broadcast, [.background, .props])]
        #expect(LayerPresence.roles(showing: .slide, screens: s) == [.audience])
    }
}

@Suite struct UI003_LibraryListingTests {
    func p(_ t: String) -> Presentation { Presentation(libraryID: UUID(), title: t, kind: .song) }

    @Test func noQueryListsTheLibrary() {
        let list = [p("A"), p("B")]
        #expect(LibraryListing.rows(query: "  ", presentations: list, hits: []).map(\.title) == ["A", "B"])
        #expect(LibraryListing.rows(query: "", presentations: list, hits: []).allSatisfy { $0.match == nil })
    }
    @Test func aQueryListsTheHitsInTheirOrderWithWhereTheyMatched() {
        let a = p("Amazing Grace"), b = p("Be Thou My Vision")
        let hits = [SearchHit(presentationID: b.id, title: b.title, matchedTitle: false),
                    SearchHit(presentationID: a.id, title: a.title, matchedTitle: true)]
        let rows = LibraryListing.rows(query: "grace", presentations: [a, b], hits: hits)
        #expect(rows.map(\.title) == ["Be Thou My Vision", "Amazing Grace"])
        #expect(rows.map(\.match) == [.lyrics, .title])
    }
    @Test func aQueryWithNoHitsListsNothing() {
        #expect(LibraryListing.rows(query: "zzz", presentations: [p("A")], hits: []).isEmpty)
    }
    @Test func searchKeepsTheMeaningOfTheTwoKeys() {
        #expect(LibraryListing.hasQuery("x") && !LibraryListing.hasQuery(" \n"))
    }
}

@Suite struct UI003_MediaControllerChoiceTests {
    @Test func aClipOverTheSlideComesFirstThenSoundThenTheBackgroundVideo() {
        let cue = UUID()
        #expect(MediaController.pick(foregroundLoaded: true, currentAudioCue: cue, backgroundIsVideo: true) == .foregroundClip)
        #expect(MediaController.pick(foregroundLoaded: false, currentAudioCue: cue, backgroundIsVideo: true) == .audioCue(cue))
        #expect(MediaController.pick(foregroundLoaded: false, currentAudioCue: nil, backgroundIsVideo: true) == .backgroundLoop)
    }
    @Test func nothingLoadedMeansNoRow() {
        #expect(MediaController.pick(foregroundLoaded: false, currentAudioCue: nil, backgroundIsVideo: false) == nil)
    }
}

@Suite struct UI003_EditLiveControlTests {
    @Test func theLiveEditHasItsOwnWordsKeyAndWarning() {
        let c = HeaderChrome.Control.editLiveSlide
        #expect(c.title == "Edit live slide…" && c.keyHint == "⌥⌘E")
        #expect(c.tooltip.contains("audience sees now"))
        #expect(c.accessibilityLabel == "Edit live slide")
    }
}

@Suite struct UI003_MediaTileMarkTests {
    func asset(_ kind: MediaKind) -> MediaAsset { MediaAsset(name: "x", kind: kind, path: "/m/x") }

    @Test func redOnlyWhileItIsOnScreenNow() {
        let a = asset(.video)
        var layers = MediaLayers()
        layers.setBackground(MediaSelection(asset: a), at: 0)
        #expect(MediaTileMarks.mark(for: a, layers: layers, showIsLive: true, selected: nil, soundIsPlaying: false) == .live)
        #expect(MediaTileMarks.mark(for: a, layers: layers, showIsLive: false, selected: nil, soundIsPlaying: false) == .preview)
    }
    @Test func aClipOverTheSlideIsLiveOnlyWithTheShowLive() {
        let a = asset(.video)
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(asset: a), at: 0)
        #expect(MediaTileMarks.mark(for: a, layers: layers, showIsLive: true, selected: nil, soundIsPlaying: false) == .live)
    }
    @Test func aSelectedTileThatIsNotOnScreenIsBlue() {
        let a = asset(.image)
        #expect(MediaTileMarks.mark(for: a, layers: MediaLayers(), showIsLive: true, selected: a.id, soundIsPlaying: false) == .preview)
        #expect(MediaTileMarks.mark(for: a, layers: MediaLayers(), showIsLive: true, selected: nil, soundIsPlaying: false) == .none)
    }
    @Test func soundIsNeverRed() {
        let s = asset(.audio)
        #expect(MediaTileMarks.mark(for: s, layers: MediaLayers(), showIsLive: true, selected: nil, soundIsPlaying: true) == .playingSound)
        #expect(MediaTileMarks.mark(for: s, layers: MediaLayers(), showIsLive: true, selected: s.id, soundIsPlaying: false) == .preview)
    }
}
