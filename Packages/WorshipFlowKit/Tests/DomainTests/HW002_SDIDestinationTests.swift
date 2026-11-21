// HW-002 / OUT-005: SDI destinations, mirrors and video mode in the Domain, and decoding of profiles stored before they existed.
import Testing
import Foundation
@testable import Domain

@Suite struct HW002_SDIDestinationTests {
    @Test func sdiDestinationRoundTripsThroughJSON() throws {
        let d = OutputDestination.sdi(deviceID: "duo2-1", connector: 3, keying: true, fillAlphaMode: .straight)
        let back = try JSONDecoder().decode(OutputDestination.self, from: JSONEncoder().encode(d))
        #expect(back == d)
        #expect(d != .sdi(deviceID: "duo2-1", connector: 3, keying: true, fillAlphaMode: .premultiplied))
    }

    @Test func aProfileStoredBeforeMirrorsAndModesStillDecodes() throws {
        // Exactly what OUT-002 wrote: no "mirrors" and no "videoMode" keys.
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","name":"Audience","role":"audience","destination":{"display":{"_0":2}},"isEnabled":true}
        """
        let p = try JSONDecoder().decode(ScreenProfile.self, from: Data(json.utf8))
        #expect(p.id == id && p.destination == .display(2) && p.isEnabled)
        #expect(p.mirrors.isEmpty)
        #expect(p.videoMode == .hd1080p5994)
    }

    @Test func aProfileWithMirrorsAndAModeRoundTrips() throws {
        var p = ScreenProfile(name: "Broadcast", role: .broadcast,
                              destination: .sdi(deviceID: "x", connector: 1, keying: true, fillAlphaMode: .premultiplied))
        p.mirrors = [.window, .display(4)]
        p.videoMode = .hd1080p50
        let back = try JSONDecoder().decode(ScreenProfile.self, from: JSONEncoder().encode(p))
        #expect(back == p)
        #expect(back.mirrors == [.window, .display(4)])
        #expect(back.videoMode.name == "1080p50")
    }

    @Test func newProfilesDefaultToNoMirrorsAndTheStandardMode() {
        let p = ScreenProfile(name: "A", role: .audience, destination: .window)
        #expect(p.mirrors.isEmpty)
        #expect(p.videoMode == .hd1080p5994)
        #expect(p.videoMode.width == 1920 && p.videoMode.height == 1080)
        #expect(p.videoMode.frameDurationValue == 1001 && p.videoMode.timeScale == 60000)
    }

    @Test func destinationQueries() {
        let keyed = OutputDestination.sdi(deviceID: "x", connector: 1, keying: true, fillAlphaMode: .premultiplied)
        let plain = OutputDestination.sdi(deviceID: "x", connector: 2, keying: false, fillAlphaMode: .premultiplied)
        #expect(keyed.isKeyed && !plain.isKeyed && !OutputDestination.window.isKeyed)
        #expect(keyed.isSDI && plain.isSDI && !OutputDestination.display(1).isSDI)
    }

    @Test func fiftyNineNineFourAndSixtyAreDifferentModes() {
        #expect(VideoModeDescription.hd1080p5994 != VideoModeDescription.hd1080p60)
        #expect(VideoModeDescription.allKnown.contains(.hd1080p5994))
        #expect(VideoModeDescription.allKnown.count == Set(VideoModeDescription.allKnown).count)
    }

    /// The display router (OUT-002) leaves SDI destinations to the combined planner: they are neither assigned nor faulted.
    @Test func displayRouterIgnoresSDIPrimaries() {
        let sdi = ScreenProfile(name: "Key", role: .broadcast,
                                destination: .sdi(deviceID: "x", connector: 1, keying: false, fillAlphaMode: .premultiplied))
        let win = ScreenProfile(name: "Stage", role: .stage, destination: .window)
        let plan = OutputRouter.plan(profiles: [sdi, win], availableDisplays: [1], operatorDisplay: nil)
        #expect(plan.assignments == [win.id: .window])
        #expect(plan.faults.isEmpty)
    }
}
