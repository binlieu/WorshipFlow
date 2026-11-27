// UI-005b item 1: the small rows UI-005a left open. Toolbar timer format, language names in Quick edit, "Saved N s ago" from a
// real save with an injected clock, and the arrangement control for a song opened from the library.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI005b_SmallRowsTests {
    // MARK: Toolbar timer format (the picture: "Service 00:10:32", "Sermon 25:00")

    @Test func anElapsedTimerReadsHoursMinutesSecondsAndACountdownReadsMinutesSeconds() async throws {
        let clock = TestClock()
        let model = StageModel(store: try LibraryStore.inMemory(), now: { clock.date }, calendar: StageModelTests.utc)
        await model.load()
        let sermon = try #require(model.addCountdown(name: "Sermon", minutes: 25, seconds: 0))
        let service = try #require(model.addElapsed(name: "Service"))
        model.toggleToolbarTimer(sermon.id)
        model.startTimer(service.id)
        clock.advance(632)
        let rows = model.toolbarTimerRows(at: model.nowSeconds)
        #expect(rows.first { $0.id == service.id }?.toolbarText == "00:10:32")
        // The countdown has run 632 s of 1500.
        #expect(rows.first { $0.id == sermon.id }?.toolbarText == "14:28")
        #expect(rows.first { $0.id == service.id }?.text == "10:32")        // the model's own format is unchanged
    }

    @Test func theToolbarFormatPadsAndKeepsHoursOnlyWhenNeeded() {
        #expect(TimeFormat.toolbar(seconds: 0, elapsed: true) == "00:00:00")
        #expect(TimeFormat.toolbar(seconds: 3725, elapsed: true) == "01:02:05")
        #expect(TimeFormat.toolbar(seconds: 1500, elapsed: false) == "25:00")
        #expect(TimeFormat.toolbar(seconds: 5400, elapsed: false) == "01:30:00")
        #expect(TimeFormat.toolbar(seconds: -5, elapsed: false) == "-00:05")
    }

    // MARK: Language names

    @Test func labelsAreTheLanguagesOfTheWordsAndFallBackToTheOldWordsWhenUnsure() async throws {
        #expect(LanguageNaming.name(of: ["Amazing grace, how sweet the sound that saved a wretch like me"]) == "English")
        let vi = LanguageNaming.name(of: ["Ân điển lạ lùng thay, đã cứu vớt tôi, xiềng xích đã tan, tôi được tự do"])
        #expect(vi == "Tiếng Việt")
        #expect(LanguageNaming.name(of: ["", "  "]) == nil)
        #expect(LanguageNaming.name(of: ["ok"]) == nil)                      // too short to judge: no guess drawn as a fact
    }

    @Test func theOpenSongNamesItsTwoFields() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let en = "Verse 1\nAmazing grace, how sweet the sound\nThat saved a wretch like me\n\nChorus\nThrough many dangers\ntoils and snares"
        let vi = "Câu 1\nÂn điển lạ lùng thay\nĐã cứu vớt tôi\n\nĐiệp khúc\nQua bao hiểm nguy\ngian khó thử thách"
        let song = try #require(await model.importLyrics(title: "Grace", primaryText: en, secondaryText: vi, maxLines: 2))
        await model.openPresentation(song.id)
        #expect(model.quickEditLanguageNames.first == "English")
        #expect(model.quickEditLanguageNames.second == "Tiếng Việt")
        let single = try #require(await model.importLyrics(title: "Solo", primaryText: en, secondaryText: nil, maxLines: 2))
        await model.openPresentation(single.id)
        #expect(model.quickEditLanguageNames.second == "Second language")
    }

    // MARK: Saved N s ago

    @Test func theNoteWordsFollowTheElapsedSeconds() {
        #expect(QuickEditLabels.savedNote(secondsAgo: nil) == "No edits yet · live at next trigger")
        #expect(QuickEditLabels.savedNote(secondsAgo: 0) == "Saved 0 s ago · live at next trigger")
        #expect(QuickEditLabels.savedNote(secondsAgo: 2) == "Saved 2 s ago · live at next trigger")
        #expect(QuickEditLabels.savedNote(secondsAgo: 125) == "Saved 2 min ago · live at next trigger")
        #expect(QuickEditLabels.savedNote(secondsAgo: 7300) == "Saved 2 h ago · live at next trigger")
    }

    @Test func theNoteCountsFromTheRealSaveOnTheInjectedClock() async throws {
        let store = try LibraryStore.inMemory()
        let clock = ManualSaveClock()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let song = try #require(await model.importLyrics(title: "S", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 2))
        await model.openPresentation(song.id)
        #expect(model.quickEditSavedNote() == QuickEditLabels.savedNote(secondsAgo: nil))
        model.editSlide(id: model.slides[0].id, content: SlideContent(primary: "typed"))
        #expect(model.quickEditSavedNote() == QuickEditLabels.savedNote(secondsAgo: nil))   // typed, not saved yet
        await clock.advance(by: 2)                                                           // the debounced write happens
        #expect(!model.hasUnsavedDrafts)
        #expect(model.quickEditSavedNote() == "Saved 0 s ago · live at next trigger")
        await clock.advance(by: 7)
        #expect(model.quickEditSavedNote() == "Saved 7 s ago · live at next trigger")
    }

    // MARK: Arrangement for a song opened from the library

    @Test func aSongOpenedFromTheLibraryCanPreviewASectionOrderWithoutTouchingLive() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let text = "Verse 1\nOne\n\nChorus\nTwo"
        let a = try #require(await model.importLyrics(title: "A", primaryText: text, secondaryText: nil, maxLines: 2))
        let other = try #require(await model.importLyrics(title: "Other", primaryText: "Verse 1\nLive words", secondaryText: nil, maxLines: 2))
        await model.openPresentation(other.id)
        await model.goLive()
        await model.openPresentation(a.id)
        let chorus = try #require(model.groups.first { $0.name == "Chorus" })
        let order = try #require(await model.createArrangement(name: "Chorus only", groupIDs: [chorus.id]))
        #expect(model.openPlaylistItemID == nil)
        let liveBefore = model.show.liveSlide
        await model.setPreviewArrangement(order.id)
        #expect(model.slides.map(\.content.primary) == ["Two"])
        #expect(model.previewArrangementID == order.id)
        #expect(model.show.liveSlide == liveBefore && liveBefore?.primary == "Live words")
        await model.setPreviewArrangement(nil)
        #expect(model.slides.map(\.content.primary) == ["One", "Two"])
        await model.setPreviewArrangement(order.id)
        await model.openPresentation(other.id)                                // another song: the choice does not follow
        #expect(model.previewArrangementID == nil)
    }
}
