// FIX-B R6: image availability is checked only for images in use, and off the main thread.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct ImageUsageTests {
    let audience = ScreenProfile(name: "Audience", role: .audience, destination: .window)
    let stage = ScreenProfile(name: "Stage", role: .stage, destination: .window)
    let broadcast = ScreenProfile(name: "Broadcast", role: .broadcast, destination: .window)

    func imageTheme(_ path: String) -> Theme {
        var theme = Theme.fullScreen
        theme.id = UUID()
        theme.name = path
        theme.background = .image(path: path)
        return theme
    }

    func prop(_ path: String, on: Bool = true) -> Prop {
        Prop(name: path, imagePath: path, frame: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1), isOn: on)
    }

    @Test func onlyPropsThatAreOnAreInUse() {
        let paths = ImageUsage.pathsInUse(props: [prop("/p/on.png"), prop("/p/off.png", on: false)], themes: Theme.builtIn,
                                          profiles: [audience], look: nil, presentationThemeID: nil)
        #expect(paths == ["/p/on.png"])
    }

    @Test func aThemeNobodyUsesIsNotChecked() {
        let unused = imageTheme("/bg/unused.png")
        let paths = ImageUsage.pathsInUse(props: [], themes: Theme.builtIn + [unused], profiles: [audience], look: nil,
                                          presentationThemeID: nil)
        #expect(paths.isEmpty)
    }

    @Test func theThemeAScreenOrTheLivePresentationUsesIsChecked() {
        let forScreen = imageTheme("/bg/screen.png"), forSong = imageTheme("/bg/song.png")
        var look = Look(id: UUID(), name: "L")
        look.screens[broadcast.id] = ScreenLook(themeID: forScreen.id, visibleLayers: Set(LayerKind.allCases))
        let themes = Theme.builtIn + [forScreen, forSong]
        #expect(ImageUsage.pathsInUse(props: [], themes: themes, profiles: [audience, broadcast], look: look,
                                      presentationThemeID: forSong.id) == ["/bg/screen.png", "/bg/song.png"])
    }

    @Test func aStageScreenADisabledScreenAndAHiddenLayerDrawNothing() {
        let bg = imageTheme("/bg/a.png")
        var disabled = audience
        disabled.isEnabled = false
        #expect(ImageUsage.pathsInUse(props: [prop("/p/x.png")], themes: Theme.builtIn + [bg], profiles: [stage, disabled], look: nil,
                                      presentationThemeID: bg.id).isEmpty)
        var look = Look(id: UUID(), name: "L")
        look.screens[audience.id] = ScreenLook(themeID: nil, visibleLayers: [.slide])          // no background, no props
        #expect(ImageUsage.pathsInUse(props: [prop("/p/x.png")], themes: Theme.builtIn + [bg], profiles: [audience], look: look,
                                      presentationThemeID: bg.id).isEmpty)
    }
}

private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var onMain = false
    private var count = 0
    private var gone: Set<String> = []
    func readable(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        count += 1
        if Thread.isMainThread { onMain = true }
        return !gone.contains(path)
    }
    func lose(_ path: String) { lock.lock(); gone.insert(path); lock.unlock() }
    func restore(_ path: String) { lock.lock(); gone.remove(path); lock.unlock() }
    var calledOnMainThread: Bool { lock.lock(); defer { lock.unlock() }; return onMain }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor
@Suite struct ImageAvailabilityMonitorTests {
    @Test func theFilesAreCheckedOffTheMainThreadAndTheResultComesBack() async {
        let probe = Probe()
        probe.lose("/b.png")
        let monitor = ImageAvailabilityMonitor(isReadable: { probe.readable($0) })
        var delivered: [[String]] = []
        monitor.onChange = { delivered.append($0) }
        monitor.check(["/a.png", "/b.png"])
        #expect(monitor.unreadable.isEmpty)                 // nothing is decided on the calling thread
        await monitor.settle()
        #expect(monitor.unreadable == ["/b.png"])
        #expect(delivered == [["/b.png"]])
        #expect(probe.calls == 2 && !probe.calledOnMainThread)
    }

    @Test func aFileThatComesBackClearsTheProblemOnTheNextCheck() async {
        let probe = Probe()
        probe.lose("/a.png")
        let monitor = ImageAvailabilityMonitor(isReadable: { probe.readable($0) })
        monitor.check(["/a.png"]); await monitor.settle()
        #expect(monitor.unreadable == ["/a.png"])
        probe.restore("/a.png")
        monitor.check(["/a.png"]); await monitor.settle()
        #expect(monitor.unreadable.isEmpty)
    }

    @Test func aBurstOfChecksRunsOneAtATimeAndTheLastPathsWin() async {
        let probe = Probe()
        probe.lose("/last.png")
        let monitor = ImageAvailabilityMonitor(isReadable: { probe.readable($0) })
        for i in 0..<5 { monitor.check(["/\(i).png"]) }
        monitor.check(["/last.png"])
        await monitor.settle()
        #expect(monitor.unreadable == ["/last.png"])
        #expect(probe.calls <= 3)                           // the first, and the last: not one pass per call
    }

    @Test func nothingInUseMeansNoFileSystemCalls() async {
        let probe = Probe()
        let monitor = ImageAvailabilityMonitor(isReadable: { probe.readable($0) })
        monitor.check([]); await monitor.settle()
        #expect(probe.calls == 0 && monitor.unreadable.isEmpty)
    }
}
