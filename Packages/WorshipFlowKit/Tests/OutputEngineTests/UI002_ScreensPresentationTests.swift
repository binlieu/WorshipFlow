// UI-002 Part 2: the words of the Screens mode that depend on facts: verification level, keyed-preview captions, the fixed
// failure text. The level is never higher than what has been measured.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

@Suite struct UI002_ScreensPresentationTests {
    @Test func aSimulatedCardIsLabelledSimulated() {
        let v = ScreensPresentation.verification(for: .simulatedDuo2)
        #expect(v.level == "Simulated")
        #expect(v.text.contains("simulated card") && v.text.contains("Hardware Verified"))
    }
    @Test func aRealCardIsImplementedAndNotHardwareVerified() {
        let real = SDIDeviceInfo(displayName: "DeckLink Duo 2", connectorCount: 4, supportsExternalKeying: true, isSimulated: false)
        let v = ScreensPresentation.verification(for: real)
        #expect(v.level == "Implemented, not hardware verified")
        #expect(!v.text.contains("passed"))
    }
    @Test func noCardMeansNoSDILevelAtAll() {
        #expect(ScreensPresentation.verification(for: nil).level == "No SDI card")
    }

    @Test func keyedCaptionsNameTheConnectorsTheDeviceReports() {
        let dest = OutputDestination.sdi(deviceID: "d", connector: 1, keying: true, fillAlphaMode: .premultiplied)
        let c = ScreensPresentation.keyedCaptions(destination: dest, device: .simulatedDuo2WithReversedKeyRoute)
        #expect(c?.fill == "SDI 2 · Fill" && c?.fillDetail == "premultiplied colour")
        #expect(c?.key == "SDI 1 · Key" && c?.keyDetail == "matte: white opaque")
        #expect(c?.composite == "Composite" && c?.compositeDetail == "what the keyer produces")
    }
    @Test func straightAlphaIsNamedStraight() {
        let dest = OutputDestination.sdi(deviceID: "d", connector: 3, keying: true, fillAlphaMode: .straight)
        #expect(ScreensPresentation.keyedCaptions(destination: dest, device: nil)?.fill == "SDI 3 · Fill")
        #expect(ScreensPresentation.keyedCaptions(destination: dest, device: nil)?.fillDetail == "straight colour")
    }
    @Test func onlyAKeyedScreenHasKeyedCaptions() {
        #expect(ScreensPresentation.keyedCaptions(destination: .window, device: nil) == nil)
        #expect(ScreensPresentation.keyedCaptions(destination: .sdi(deviceID: "d", connector: 1, keying: false, fillAlphaMode: .premultiplied), device: nil) == nil)
    }

    @Test func fixedWording() {
        #expect(ScreensPresentation.blackIsNotTransparency.headline == "A black background is not transparency.")
        #expect(ScreensPresentation.blackIsNotTransparency.body.contains("fill carries colour"))
        #expect(ScreensPresentation.outputFailureText.contains("show keeps running"))
    }
}
