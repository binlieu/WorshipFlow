// FIX-B R6: which image files the screens draw right now, and a checker that asks the file system off the main thread.
// A stat on a sleeping or missing network volume can hang for many seconds; it must never happen on the main thread.
// Foundation only.
import Foundation
import Domain

public enum ImageUsage {
    /// Image paths the enabled audience and broadcast screens would draw now: props that are on (when the screen shows
    /// the props layer) and the background image of the theme each screen resolves to (when it shows the background
    /// layer). A stage screen draws neither. Themes nobody uses are not listed.
    public static func pathsInUse(props: [Prop], themes: [Theme], profiles: [ScreenProfile], look: Look?,
                                  presentationThemeID: UUID?) -> Set<String> {
        var paths = Set<String>()
        for profile in profiles where profile.isEnabled && profile.role != .stage {
            let screenLook = look?.screenLook(for: profile.id, in: profiles) ?? .standard
            if screenLook.visibleLayers.contains(.props) {
                for prop in props where prop.isOn && prop.kind == .image && prop.targets.contains(profile.role) { paths.insert(prop.imagePath) }
            }
            if screenLook.visibleLayers.contains(.background) {
                let theme = ThemeResolver.theme(for: profile.role, lookThemeID: screenLook.themeID,
                                                presentationThemeID: presentationThemeID, themes: themes)
                if case .image(let path) = theme.background { paths.insert(path) }
            }
        }
        return paths
    }
}

/// Checks whether files can be read, on a background thread, one pass at a time. `check` returns at once; the result
/// arrives in `unreadable` and `onChange` on the main actor.
@MainActor
public final class ImageAvailabilityMonitor {
    private let isReadable: @Sendable (String) -> Bool
    private var running: Task<Void, Never>?
    private var queued: Set<String>?

    /// The paths of the last pass that could not be read, sorted.
    public private(set) var unreadable: [String] = []
    public var onChange: (@MainActor ([String]) -> Void)?

    public init(isReadable: @escaping @Sendable (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) }) {
        self.isReadable = isReadable
    }

    /// Starts a pass over `paths`, or, if one is running, makes these the paths of the next pass (earlier queued ones are dropped).
    public func check(_ paths: Set<String>) {
        if running != nil { queued = paths; return }
        start(paths)
    }

    /// Returns when no pass is running or queued. For tests.
    public func settle() async {
        while let task = running { await task.value }
    }

    private func start(_ paths: Set<String>) {
        let probe = isReadable
        running = Task { @MainActor [weak self] in
            let missing = await Task.detached(priority: .utility) { paths.filter { !probe($0) }.sorted() }.value
            guard let self else { return }
            self.running = nil
            if missing != self.unreadable {
                self.unreadable = missing
                self.onChange?(missing)
            }
            if let next = self.queued {
                self.queued = nil
                self.start(next)
            }
        }
    }
}
