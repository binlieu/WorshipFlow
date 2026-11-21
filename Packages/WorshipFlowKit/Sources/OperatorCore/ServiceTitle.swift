// UI-005b: the toolbar title the design draws, "Sunday 9:00 — 22 Nov", written for the user's locale from the playlist's service date
// and time. The locale and calendar are passed in (the calendar carries the time zone), so nothing here reads a clock.
import Foundation

public enum ServiceTitle {
    /// With a date: weekday, time of day and day with month, in the locale's own order and clock style. Without one: the name.
    public static func text(name: String, serviceAt: Date?, locale: Locale, calendar: Calendar) -> String {
        guard let serviceAt else { return name }
        func format(_ template: String) -> String {
            let f = DateFormatter()
            f.locale = locale
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate(template)
            return f.string(from: serviceAt)
        }
        return "\(format("EEEE")) \(format("jmm")) — \(format("dMMM"))"
    }
}

extension WorkspaceModel {
    /// The window title: the selected playlist's service date as above, or its name; "No playlist" when there is none.
    public func serviceTitle(locale: Locale = .current, calendar: Calendar = .current) -> String {
        guard let playlist = playlists.first(where: { $0.id == selectedPlaylistID }) else { return "No playlist" }
        return ServiceTitle.text(name: playlist.name, serviceAt: playlist.serviceAt, locale: locale, calendar: calendar)
    }

    /// Sets or removes the service date and time of a playlist. Nothing else changes, and Live is not touched.
    public func setServiceDate(_ date: Date?, forPlaylist id: UUID) async {
        guard await attempt("set the service date", { try await self.store.setPlaylistServiceDate(id: id, to: date) }) != nil else { return }
        await reloadPlaylists()
    }
}
