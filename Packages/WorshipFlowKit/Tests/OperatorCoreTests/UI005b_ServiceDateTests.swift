// UI-005b item 2: a playlist's service date and time, and the toolbar title that reads from it ("Sunday 9:00 — 22 Nov"), formatted
// for the user's locale from an injected locale, calendar and date. No clock is read.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI005b_ServiceDateTests {
    /// Sunday 22 November 2026, 09:00 UTC.
    static let sunday = Date(timeIntervalSince1970: 1_795_338_000)
    static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test func theTitleReadsWeekdayTimeAndDateInTheUsersLocale() {
        #expect(ServiceTitle.text(name: "Service", serviceAt: Self.sunday, locale: Locale(identifier: "en_GB"), calendar: Self.utc) == "Sunday 09:00 — 22 Nov")
        // The system puts a narrow no-break space before AM; it is the same text to the eye.
        let us = ServiceTitle.text(name: "Service", serviceAt: Self.sunday, locale: Locale(identifier: "en_US"), calendar: Self.utc)
        #expect(us.replacingOccurrences(of: "\u{202F}", with: " ") == "Sunday 9:00 AM — Nov 22")
        let vi = ServiceTitle.text(name: "Service", serviceAt: Self.sunday, locale: Locale(identifier: "vi_VN"), calendar: Self.utc)
        #expect(vi.hasPrefix("Chủ Nhật") && vi.contains("09:00") && vi.contains("—"))
    }

    @Test func theTimeZoneOfTheCalendarDecidesTheClockTime() {
        var tokyo = Self.utc
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        #expect(ServiceTitle.text(name: "Service", serviceAt: Self.sunday, locale: Locale(identifier: "en_GB"), calendar: tokyo) == "Sunday 18:00 — 22 Nov")
    }

    @Test func withoutADateTheTitleIsThePlaylistName() {
        #expect(ServiceTitle.text(name: "Sunday 9:00", serviceAt: nil, locale: Locale(identifier: "en_GB"), calendar: Self.utc) == "Sunday 9:00")
    }

    @Test func theModelSetsAndClearsTheDateAndTheToolbarTitleFollows() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let playlist = try #require(model.playlists.first)
        #expect(model.serviceTitle(locale: Locale(identifier: "en_GB"), calendar: Self.utc) == playlist.name)
        await model.setServiceDate(Self.sunday, forPlaylist: playlist.id)
        #expect(model.playlists.first?.serviceAt == Self.sunday)
        #expect(model.serviceTitle(locale: Locale(identifier: "en_GB"), calendar: Self.utc) == "Sunday 09:00 — 22 Nov")
        #expect(try await store.playlists().first?.serviceAt == Self.sunday)         // stored, not only held
        await model.renamePlaylist(id: playlist.id, to: "Morning")
        #expect(model.playlists.first?.serviceAt == Self.sunday)                      // a rename keeps the date
        await model.setServiceDate(nil, forPlaylist: playlist.id)
        #expect(model.serviceTitle(locale: Locale(identifier: "en_GB"), calendar: Self.utc) == "Morning")
    }

    @Test func settingTheDateNeverTouchesLive() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let song = try #require(await model.importLyrics(title: "S", primaryText: "words", secondaryText: nil, maxLines: 2))
        await model.addToPlaylist(song.id)
        await model.openPlaylistItem(model.playlistItems[0].id)
        await model.goLive()
        let live = model.show.liveSlide
        await model.setServiceDate(Self.sunday, forPlaylist: try #require(model.selectedPlaylistID))
        #expect(model.show.liveSlide == live && live?.primary == "words")
    }
}
