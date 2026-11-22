// FIX-J item 6 (UI-005h): the output themes name Inter; when the bundled font could not be loaded the operator is told once and the hardware
// test environment records it.
import Testing
import Foundation
import CoreText
import Domain
@testable import RenderEngine

@Suite struct FIXJ_OutputFontTests {
    @Test func theThemesNameTheBundledInter() {
        #expect(Theme.fullScreen.primary.style.fontName == Theme.outputFontName)
        #expect(Theme.lowerThird.primary.style.fontName == Theme.outputFontName)
        #expect(StageLayout.standard.elements.allSatisfy { $0.style.fontName == Theme.outputFontName })
    }

    @Test func withInterRegisteredTheCheckSaysSoAndThereIsNothingToTell() {
        #expect(UI005hFixtures.registerInter())
        let status = OutputFont.check()
        #expect(status.isInter, "resolved to \(status.resolvedName)")
        #expect(status.operatorNotice == nil)
        #expect(status.environmentLine.hasPrefix("Inter"))
    }

    @Test func aNameThatDoesNotResolveToInterGivesTheNoticeAndTheEnvironmentLine() {
        let status = OutputFont.check(name: "NoSuchBundledFont-WF")
        #expect(!status.isInter)
        #expect(status.operatorNotice == "The bundled font could not be loaded; screens are using a system font and line breaks may differ")
        #expect(status.environmentLine.contains("system font") && status.environmentLine.contains(status.resolvedName))
    }

    @Test func aFontThatHappensToBeNamedLikeInterButIsNotTheBundledOneIsStillTheBundledCheck() {
        // The check is on the font Core Text hands back: a system font is not Inter whatever it is asked for.
        #expect(!OutputFont.check(name: "Helvetica").isInter)
    }
}
