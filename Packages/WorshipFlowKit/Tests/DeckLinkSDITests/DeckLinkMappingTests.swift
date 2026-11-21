// HW-003: pure mappings between the SDIEngine types and the DeckLink bridge. Verification level: Unit Tested.
import DeckLinkC
import Foundation
import SDIEngine
import Testing
@testable import DeckLinkSDI

@Suite struct HW003_ModeMappingTests {
    @Test func everyKnownModeMapsToACodeAndBack() throws {
        for mode in SDIVideoMode.allKnown {
            let code = try #require(DeckLinkModeMapping.displayMode(for: mode), "no DeckLink mode for \(mode.name)")
            let back = try #require(DeckLinkModeMapping.videoMode(forDisplayMode: code), "no app mode for code \(code)")
            #expect(back == mode, "\(mode.name) came back as \(back.name)")
        }
        #expect(DeckLinkModeMapping.table.count == SDIVideoMode.allKnown.count)
    }

    @Test func theCodesAreTheSDKsBMDDisplayModeValues() {
        // Literal values from DeckLinkAPIModes.h, so a typo in the table cannot agree with itself.
        let expected: [(SDIVideoMode, UInt32)] = [
            (.hd1080p5994, 0x48703539), (.hd1080p60, 0x48703630), (.hd1080p50, 0x48703530),
            (.hd1080p2997, 0x48703239), (.hd1080p30, 0x48703330), (.hd1080p25, 0x48703235),
            (.hd1080i5994, 0x48693539), (.hd720p5994, 0x68703539), (.hd720p60, 0x68703630), (.hd720p50, 0x68703530),
        ]
        for (mode, code) in expected { #expect(DeckLinkModeMapping.displayMode(for: mode) == code, "\(mode.name)") }
        #expect(expected.count == SDIVideoMode.allKnown.count)
    }

    @Test func codesAreUniqueSoNoTwoModesShareOne() {
        let codes = DeckLinkModeMapping.table.map(\.displayMode)
        #expect(Set(codes).count == codes.count)
    }

    @Test func fiftyNineNineFourAndSixtyAreDifferentModes() {
        #expect(DeckLinkModeMapping.displayMode(for: .hd1080p5994) != DeckLinkModeMapping.displayMode(for: .hd1080p60))
        #expect(DeckLinkModeMapping.displayMode(for: .hd720p5994) != DeckLinkModeMapping.displayMode(for: .hd720p60))
    }

    @Test func interlacedAndProgressiveWithTheSameFrameDurationAreDifferentModes() {
        #expect(SDIVideoMode.hd1080i5994.frameDurationValue == SDIVideoMode.hd1080p2997.frameDurationValue)
        #expect(SDIVideoMode.hd1080i5994.timeScale == SDIVideoMode.hd1080p2997.timeScale)
        #expect(DeckLinkModeMapping.displayMode(for: .hd1080i5994) != DeckLinkModeMapping.displayMode(for: .hd1080p2997))
    }

    @Test func aModeIsMatchedOnTimingNotOnItsName() {
        let renamed = SDIVideoMode(width: 1920, height: 1080, frameDurationValue: 1001, timeScale: 60000, name: "my 59.94")
        #expect(DeckLinkModeMapping.displayMode(for: renamed) == DeckLinkModeMapping.displayMode(for: .hd1080p5994))
        let nearlyRight = SDIVideoMode(width: 1920, height: 1080, frameDurationValue: 1000, timeScale: 59940, name: "1080p59.94 rounded")
        #expect(DeckLinkModeMapping.displayMode(for: nearlyRight) == nil)
    }

    @Test func modesTheAppDoesNotOfferHaveNoMapping() {
        let uhd = SDIVideoMode(width: 3840, height: 2160, frameDurationValue: 1001, timeScale: 60000, name: "2160p59.94")
        #expect(DeckLinkModeMapping.displayMode(for: uhd) == nil)
        #expect(DeckLinkModeMapping.videoMode(forDisplayMode: 0x346B3539) == nil)   // bmdMode4K2160p5994
        #expect(DeckLinkModeMapping.videoMode(forDisplayMode: 0x69756E6B) == nil)   // bmdModeUnknown
        #expect(DeckLinkModeMapping.videoMode(forDisplayMode: 0) == nil)
    }

    @Test func fourCharacterCodesPrintReadably() {
        #expect(DeckLinkModeMapping.text(forFourCC: 0x48703539) == "Hp59")
        #expect(DeckLinkModeMapping.text(forFourCC: 0x00000001) == "0x1")
    }
}

@Suite struct HW003_CompletionAndKeyingMappingTests {
    @Test func everyBridgeResultMapsToTheMatchingEngineResult() {
        #expect(DeckLinkMapping.completionResult(.completed) == .completed)
        #expect(DeckLinkMapping.completionResult(.displayedLate) == .displayedLate)
        #expect(DeckLinkMapping.completionResult(.dropped) == .dropped)
        #expect(DeckLinkMapping.completionResult(.flushed) == .flushed)
    }

    @Test func anUnrecognisedResultIsNeverReportedAsShown() {
        #expect(DeckLinkMapping.completionResult(.unknown) == .dropped)
    }

    @Test func theBridgeRawValuesMatchTheSDKOrder() {
        // bmdOutputFrameCompleted, DisplayedLate, Dropped, Flushed are 0...3 in DeckLinkAPI.h.
        #expect(DLBCompletionResult.completed.rawValue == 0)
        #expect(DLBCompletionResult.displayedLate.rawValue == 1)
        #expect(DLBCompletionResult.dropped.rawValue == 2)
        #expect(DLBCompletionResult.flushed.rawValue == 3)
    }

    @Test func noKeyingMeansNoKeyer() {
        #expect(DeckLinkMapping.keyingPlan(.none) == .init(useKeyer: false, straightAlpha: false))
    }

    @Test func externalKeyingTurnsOnTheKeyerAndCarriesTheAlphaMode() {
        #expect(DeckLinkMapping.keyingPlan(.external(fillAlphaMode: .premultiplied)) == .init(useKeyer: true, straightAlpha: false))
        #expect(DeckLinkMapping.keyingPlan(.external(fillAlphaMode: .straight)) == .init(useKeyer: true, straightAlpha: true))
        #expect(DeckLinkMapping.bridgeAlphaMode(straight: true) == .straight)
        #expect(DeckLinkMapping.bridgeAlphaMode(straight: false) == .premultiplied)
    }

    private func bridgeError(_ code: DLBError.Code) -> NSError {
        NSError(domain: DLBErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: "detail"])
    }

    @Test func bridgeErrorsBecomeEngineErrorsAccordingToWhereTheyHappened() {
        let enableKeyed = DeckLinkMapping.Context.enable(connector: 3, modeName: "1080p59.94", keyed: true)
        let enablePlain = DeckLinkMapping.Context.enable(connector: 1, modeName: "1080p59.94", keyed: false)
        #expect(DeckLinkMapping.sdiError(bridgeError(.deviceRemoved), context: .schedule) == .deviceDisconnected)
        #expect(DeckLinkMapping.sdiError(bridgeError(.notSupported), context: enableKeyed) == .keyingUnavailable(connector: 3))
        #expect(DeckLinkMapping.sdiError(bridgeError(.notSupported), context: enablePlain) == .unsupportedMode("1080p59.94"))
        #expect(DeckLinkMapping.sdiError(bridgeError(.notSupported), context: .open(connector: 2)) == .connectorUnavailable(2))
        #expect(DeckLinkMapping.sdiError(bridgeError(.busy), context: .open(connector: 4)) == .connectorUnavailable(4))
        #expect(DeckLinkMapping.sdiError(bridgeError(.badState), context: .schedule) == .notEnabled)
        #expect(DeckLinkMapping.sdiError(bridgeError(.badState), context: enablePlain) == .portClosed)
        // HW-004 (KI-056): an SDK failure is a hardware fault carrying the SDK's words, no longer reported as "disconnected".
        #expect(DeckLinkMapping.sdiError(bridgeError(.sdkFailure), context: .schedule) == .hardwareFault(detail: "detail"))
        #expect(DeckLinkMapping.sdiError(SDIError.portClosed, context: .schedule) == .portClosed)
        if case .hardwareFault = DeckLinkMapping.sdiError(NSError(domain: "other", code: 1), context: .runtime) {} else { Issue.record("an unrecognised error is a hardware fault") }
    }

    @Test func theSDKResultCodeSurvivesInTheLogDetail() {
        let error = NSError(domain: DLBErrorDomain, code: DLBError.Code.sdkFailure.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "The card would not accept the frame.", DLBErrorHRESULTKey: -2147467259])
        #expect(DeckLinkMapping.detail(error).contains("-2147467259"))
    }
}
