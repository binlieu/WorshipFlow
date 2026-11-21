// HW-002 / OUT-005: the coordinator opens and closes SDI outputs and mirrors from the combined plan.
// SDI outputs are real `SDIOutput`s on the simulated card with a manual clock; displays and windows are fakes.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

@MainActor
final class SDIHarness {
    let device = SimulatedSDIDevice(info: .simulatedDuo2)
    var displays = DisplaySnapshot(available: [1, 2, 3], operatorDisplay: 1)
    var cardPresent = true
    var made: [FakeTarget] = []
    var madeSDI: [SDIOutput] = []
    var factoryError: Error?
    let sceneBox = HW002SceneBox()
    var coordinator: OutputCoordinator!
    var handle: SDIDeviceHandle { SDIDeviceHandle(id: "sim", device: device) }

    init(_ profiles: [ScreenProfile]) {
        sceneBox.set(lowerThirdScene())
        coordinator = OutputCoordinator(
            profiles: profiles,
            displays: { [unowned self] in self.displays },
            makeSlotTarget: { [unowned self] profile, slot, destination in
                let t = FakeTarget(name: slot.mirror.map { "\(profile.name) mirror \($0)" } ?? profile.name, destination: destination)
                self.made.append(t)
                return t
            },
            sdi: SDIEnvironment(
                devices: { [unowned self] in self.cardPresent ? [self.handle] : [] },
                makeTarget: { [unowned self] profile, setup in
                    if let e = self.factoryError { throw e }
                    let out = SDIOutput(name: profile.name, port: setup.port, mode: setup.planned.mode, keying: setup.planned.keying,
                                        isSimulated: setup.info.isSimulated, sceneProvider: { [box = self.sceneBox] in box.get() })
                    self.madeSDI.append(out)
                    return out
                }))
    }

    func readout(_ id: UUID) -> ScreenReadout? { coordinator.readouts().first { $0.id == id } }
    func settle() { for o in madeSDI where o.status == .running { o.waitUntilStarted() } }
}

func sdiDest(_ connector: Int, keying: Bool = false, alpha: SDIAlphaMode = .premultiplied, device: String = "sim") -> OutputDestination {
    .sdi(deviceID: device, connector: connector, keying: keying, fillAlphaMode: alpha)
}

@MainActor
@Suite(.serialized) struct HW002_CoordinatorSDITests {
    let program = ScreenProfile(name: "Program", role: .broadcast, destination: sdiDest(1, keying: true))
    let lobby = ScreenProfile(name: "Lobby", role: .audience, destination: sdiDest(3))
    let stage = ScreenProfile(name: "Stage", role: .stage, destination: .window)
    let sanctuary = ScreenProfile(name: "Sanctuary", role: .audience, destination: .display(2))

    @Test func startOpensAKeyedSDIOutputAndReportsItAsSimulated() throws {
        let h = SDIHarness([program, stage])
        h.coordinator.start(); h.settle()
        let r = try #require(h.readout(program.id))
        #expect(r.state == .running)
        let sdi = try #require(r.sdi)
        #expect(sdi.isSimulated && sdi.modeName == "1080p59.94" && sdi.health == .ok)
        h.device.advance(frames: 3)
        #expect(h.device.lastDisplayed(onConnector: 1) != nil && h.device.lastDisplayed(onConnector: 2) != nil)
        #expect(h.readout(stage.id)?.state == .running && h.readout(stage.id)?.sdi == nil)
        #expect(h.readout(program.id)?.presented == 3)
    }

    @Test func theConnectorMapShowsWhatEachConnectorCarries() throws {
        let h = SDIHarness([program, lobby])
        h.coordinator.start()
        let map = try #require(h.coordinator.connectorMaps()["sim"])
        #expect(map.uses == [.fill(OutputSlot(screenID: program.id)), .key(OutputSlot(screenID: program.id)),
                             .output(OutputSlot(screenID: lobby.id)), .unused])
        #expect(h.coordinator.sdiDevices().map(\.id) == ["sim"])
        h.coordinator.stop()
        #expect(h.coordinator.connectorMaps()["sim"]?.uses.count == 4)     // the plan still shows what the screens ask for
    }

    /// Acceptance: two screens asking for the same connector fault the later one; the first keeps running.
    @Test func twoScreensOnTheSameConnectorFaultTheLaterOne() throws {
        let second = ScreenProfile(name: "Second", role: .audience, destination: sdiDest(3))
        let h = SDIHarness([lobby, second])
        h.coordinator.start(); h.settle()
        #expect(h.readout(lobby.id)?.state == .running)
        #expect(h.readout(second.id)?.state == .faulted(SDIPlanFault.connectorInUse(by: lobby.id).operatorMessage))
        #expect(h.madeSDI.count == 1)
    }

    @Test func noCardMeansTheScreenIsFaultedAndOthersRun() {
        let h = SDIHarness([program, stage])
        h.cardPresent = false
        h.coordinator.start()
        #expect(h.readout(program.id)?.state == .faulted(OutputFault.sdiDeviceMissing.operatorMessage))
        #expect(h.readout(stage.id)?.state == .running)
    }

    @Test func aCardThatAppearsLaterStartsTheWaitingScreen() {
        let h = SDIHarness([program])
        h.cardPresent = false
        h.coordinator.start()
        h.cardPresent = true
        h.coordinator.devicesChanged(); h.settle()
        #expect(h.readout(program.id)?.state == .running)
    }

    /// Acceptance: unplug stops that output only and reports it; replug resumes on the same device (KI-012).
    @Test func unplugAndReplug() async throws {
        let h = SDIHarness([program, lobby, stage, sanctuary])
        h.coordinator.start(); h.settle()
        h.device.advance(frames: 5)
        h.device.simulateUnplug()
        #expect(await waitFor { if case .faulted = h.readout(program.id)?.state { return true } else { return false } })
        guard case .faulted(let message)? = h.readout(program.id)?.state else { Issue.record("expected a fault"); return }
        #expect(message.contains("SDI card"))
        #expect(await waitFor { if case .faulted = h.readout(lobby.id)?.state { return true } else { return false } })
        #expect(h.readout(stage.id)?.state == .running && h.readout(sanctuary.id)?.state == .running)   // only SDI outputs stop
        // The card is back: the screens resume, on the same device, with new ports.
        h.device.simulateReplug()
        h.coordinator.devicesChanged(); h.settle()
        #expect(h.readout(program.id)?.state == .running && h.readout(lobby.id)?.state == .running)
        h.device.advance(frames: 5)
        #expect(h.readout(program.id)?.presented == 5)
        #expect(h.madeSDI.count == 4)
    }

    /// The card was unplugged and plugged back before the output got to report the loss: it still comes back by itself.
    @Test func aQuickUnplugAndReplugStillResumes() async throws {
        let h = SDIHarness([lobby])
        h.coordinator.start(); h.settle()
        h.device.simulateUnplug()
        h.device.simulateReplug()
        #expect(await waitFor { h.madeSDI.count == 2 && h.readout(lobby.id)?.state == .running })
        h.settle()
        h.device.advance(frames: 3)
        #expect(h.readout(lobby.id)?.presented == 3)
    }

    @Test func anOperatorStoppedSDIScreenStaysStoppedWhenTheCardReturns() async throws {
        let h = SDIHarness([program, lobby])
        h.coordinator.start(); h.settle()
        h.coordinator.stop(lobby.id)
        h.device.simulateUnplug()
        #expect(await waitFor { if case .faulted = h.readout(program.id)?.state { return true } else { return false } })
        h.device.simulateReplug()
        h.coordinator.devicesChanged(); h.settle()
        #expect(h.readout(program.id)?.state == .running)
        #expect(h.readout(lobby.id)?.state == .stopped)
    }

    @Test func aFactoryFailureFaultsThatScreenAndFreesTheConnector() throws {
        struct Boom: Error {}
        let h = SDIHarness([lobby])
        h.factoryError = Boom()
        h.coordinator.start()
        guard case .faulted? = h.readout(lobby.id)?.state else { Issue.record("expected a fault"); return }
        _ = try h.device.openOutput(connector: 3)        // the port the coordinator opened was closed again
    }

    @Test func stoppingAScreenGivesItsConnectorsBack() throws {
        let h = SDIHarness([program])
        h.coordinator.start(); h.settle()
        h.coordinator.stop(program.id)
        _ = try h.device.openOutput(connector: 1)
        _ = try h.device.openOutput(connector: 2)
    }

    @Test func aModeTheCardLacksFaultsTheScreen() {
        var p = lobby; p.videoMode = VideoModeDescription(width: 640, height: 480, frameDurationValue: 1000, timeScale: 30000, name: "480p30")
        let h = SDIHarness([p])
        h.coordinator.start()
        #expect(h.readout(p.id)?.state == .faulted(OutputFault.sdiModeUnsupported("480p30").operatorMessage))
    }

    @Test func theScreenRunsInItsOwnVideoMode() throws {
        var p = lobby; p.videoMode = .hd720p50
        let h = SDIHarness([p])
        h.coordinator.start(); h.settle()
        h.device.advance(frames: 2)
        let shown = try #require(h.device.lastDisplayed(onConnector: 3))
        #expect(shown.width == 1280 && shown.height == 720)
        #expect(h.readout(p.id)?.sdi?.modeName == "720p50")
        #expect(h.readout(p.id)?.refreshRate == 50)
    }

    // MARK: mirrors

    @Test func aMirrorRunsBesideItsPrimaryAndHasItsOwnStatus() throws {
        var p = sanctuary; p.mirrors = [.window, sdiDest(3)]
        let h = SDIHarness([p])
        h.coordinator.start(); h.settle()
        let r = try #require(h.readout(p.id))
        #expect(r.state == .running)
        #expect(r.mirrors.count == 2)
        #expect(r.mirrors.allSatisfy { $0.state == .running })
        #expect(r.mirrors[0].destination == .window)
        #expect(r.mirrors[1].sdi?.isSimulated == true)
        #expect(h.coordinator.runningCount == 3)
    }

    @Test func aMissingMirrorDisplayFaultsTheMirrorAndNotThePrimary() throws {
        var p = sanctuary; p.mirrors = [.display(9), .window]
        let h = SDIHarness([p])
        h.coordinator.start()
        let r = try #require(h.readout(p.id))
        #expect(r.state == .running)
        #expect(r.mirrors[0].state == .faulted(RoutingFault.displayMissing.operatorMessage))
        #expect(r.mirrors[1].state == .running)
    }

    @Test func aMirrorDisplayThatReturnsResumesOnTheSameDisplay() throws {
        var p = sanctuary; p.mirrors = [.display(3)]
        let h = SDIHarness([p])
        h.coordinator.start()
        h.displays = DisplaySnapshot(available: [1, 2], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        #expect(h.readout(p.id)?.state == .running)
        guard case .faulted? = h.readout(p.id)?.mirrors[0].state else { Issue.record("mirror should be faulted"); return }
        h.displays = DisplaySnapshot(available: [1, 2, 3], operatorDisplay: 1)
        h.coordinator.displaysChanged()
        #expect(h.readout(p.id)?.mirrors[0].state == .running)
        #expect(h.made.last?.destination == .display(3))
        #expect(h.readout(p.id)?.state == .running)
        #expect(h.made.filter { $0.name == "Sanctuary" }.count == 1)           // the primary was never restarted
    }

    @Test func addingAMirrorStartsOnlyTheMirror() throws {
        let h = SDIHarness([sanctuary, stage])
        h.coordinator.start()
        var p = sanctuary; p.mirrors = [.window]
        h.coordinator.setProfiles([p, stage])
        #expect(h.made.filter { $0.name == "Sanctuary" }.first?.stopCount == 0)
        #expect(h.made.count == 3)
        #expect(h.readout(p.id)?.mirrors.first?.state == .running)
        p.mirrors = []
        h.coordinator.setProfiles([p, stage])
        #expect(h.readout(p.id)?.mirrors.isEmpty == true)
        #expect(h.made.first { $0.name == "Sanctuary mirror 0" }?.stopCount == 1)
        #expect(h.made.first { $0.name == "Sanctuary" }?.stopCount == 0)
        #expect(h.coordinator.runningCount == 2)
    }

    @Test func changingOneMirrorLeavesTheOthersAlone() throws {
        var p = sanctuary; p.mirrors = [.window, .display(3)]
        let h = SDIHarness([p])
        h.coordinator.start()
        var q = p; q.mirrors = [.window, .window]
        h.coordinator.setProfiles([q])
        #expect(h.made.filter { $0.name == "Sanctuary" }.first?.stopCount == 0)
        #expect(h.made.first { $0.name == "Sanctuary mirror 0" }?.stopCount == 0)
        #expect(h.made.first { $0.name == "Sanctuary mirror 1" }?.stopCount == 1)
        #expect(h.made.count == 4)
    }

    @Test func stoppingAScreenStopsItsMirrorsToo() {
        var p = sanctuary; p.mirrors = [.window, sdiDest(3)]
        let h = SDIHarness([p, stage])
        h.coordinator.start(); h.settle()
        h.coordinator.stop(p.id)
        #expect(h.coordinator.runningCount == 1)
        h.coordinator.restart(p.id); h.settle()
        #expect(h.coordinator.runningCount == 4)
    }

    @Test func aMirrorOfASDIScreenShowsTheSamePixels() throws {
        var p = lobby; p.mirrors = [sdiDest(4)]
        let h = SDIHarness([p])
        h.coordinator.start(); h.settle()
        h.device.advance(frames: 20)
        let a = try #require(h.device.lastDisplayed(onConnector: 3))
        let b = try #require(h.device.lastDisplayed(onConnector: 4))
        #expect(a == b)
    }

    @Test func aProfileWithoutAnSDIEnvironmentFaultsItsSDIScreenOnly() {
        let c = OutputCoordinator(profiles: [program, stage], displays: { DisplaySnapshot(available: [1, 2], operatorDisplay: 1) },
                                  makeTarget: { _, d in FakeTarget(name: "x", destination: d) })
        c.start()
        #expect(c.readouts().first { $0.id == program.id }?.state == .faulted(OutputFault.sdiDeviceMissing.operatorMessage))
        #expect(c.readouts().first { $0.id == stage.id }?.state == .running)
    }
}
