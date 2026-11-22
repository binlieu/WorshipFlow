// FIX-N item 2 (FIX-K, LIB-005): a program package whose slide carries a hostile text frame imports, and the slide comes in with no override.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXN_FrameValidationPackageTests {
    @Test func hostileFramesInAPackageImportAsNoOverrideAndAGoodOneIsKept() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        var n = 0
        try editSlides(package) { slide in
            n += 1
            switch n {
            case 1: slide["textFrames"] = ["primary": ["x": 0.1, "y": 0.1, "width": 0.0, "height": 0.3]]
            case 2: slide["textFrames"] = ["primary": ["x": 0.1, "y": 0.1, "width": -0.4, "height": 0.3], "secondary": ["x": 3.0, "y": 3.0, "width": 0.2, "height": 0.2]]
            default: slide["textFrames"] = ["primary": ["x": 0.1, "y": 0.2, "width": 0.5, "height": 0.25]]
            }
        }
        let contents = try ProgramPackageContents.open(package)
        let all = contents.document.presentations.flatMap(\.slides)
        #expect(all.count >= 3)
        #expect(all[0].textFrames == nil && all[1].textFrames == nil)
        #expect(all[2].textFrames?.primary == NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25))
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        let imported = try await church.slides(of: home.songTwo)
        #expect(imported.allSatisfy { $0.content.textFrames == nil || $0.content.textFrames?.primary == NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25) })
    }
}
