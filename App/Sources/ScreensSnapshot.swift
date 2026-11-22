// UI-005f (debug builds only): `UI_SNAPSHOT_SCREENS=1` with `UI_SNAPSHOT_DESIGN=1` and `UI_SNAPSHOT_SDI=1` (scripts/design-capture.sh's
// setup) captures the Screens mode at 1440 x 900 points in the state of docs/UI/screens/03-screens-outputs.png as far as today's data
// allows: the simulated card, an audience screen on SDI 3, a stage screen on SDI 4, the fill-and-key broadcast screen on SDI 1 and 2
// selected, each with the label the operator typed for where it goes. Pictures `screens-dark` and `screens-light`, with rectangles.
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import OperatorCore

extension AppModel {
    func runScreensScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void, window: NSWindow?) async {
        guard let workspace else { note("screens: no workspace"); return }
        for var profile in profiles {
            profile.isEnabled = true
            switch profile.role {
            case .audience:
                profile.name = "Sanctuary"
                profile.mirrors = []
                profile.setConnectedNote("Projector", mirror: nil)
            case .stage:
                profile.name = "Confidence"
                profile.destination = .sdi(deviceID: Self.simulatedCardID, connector: 4, keying: false, fillAlphaMode: .premultiplied)
                profile.mirrors = []
                profile.setConnectedNote("Stage monitor", mirror: nil)
            case .broadcast:
                profile.mirrors = []
                profile.setConnectedNote("ATEM input 5", mirror: nil)
            }
            updateProfile(profile)
        }
        if let broadcast = profiles.first(where: { $0.role == .broadcast }) { ui.selectedScreenID = broadcast.id }
        window?.setContentSize(NSSize(width: 1440, height: 900))
        window?.center()
        workspace.setMode(.screens)
        try? await Task.sleep(for: .seconds(2.5))
        note("screens: \(profiles.map { "\($0.name)=\($0.destination)" }.joined(separator: "; "))")
        setAppearance(.dark)
        await capture("screens-dark")
        setAppearance(.light)
        await capture("screens-light")
        setAppearance(.dark)
        // The other roles' forms, and a window destination (no SDI rows): checked by eye, not mapped to the design.
        for role in [ScreenRole.audience, .stage] {
            if let p = profiles.first(where: { $0.role == role }) { ui.selectedScreenID = p.id }
            await capture("screens-\(role.rawValue)-dark")
        }
        if var p = profiles.first(where: { $0.role == .audience }) {
            p.destination = .window
            updateProfile(p)
            ui.selectedScreenID = p.id
            try? await Task.sleep(for: .seconds(1.5))
            await capture("screens-window-dark")
        }
    }
}
#endif
