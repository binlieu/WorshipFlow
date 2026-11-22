// FIX-H item 5 (UI-005b): a damaged or imported loop with zero seconds per picture crashed the one-second tick. Values that the
// initialisers clamp are clamped the same way when they are decoded, and the index arithmetic cannot divide by zero or overflow.
// The other types UI-005b added that validate in `init` with a synthesised Codable (`TextPropSpec`, `Prop`) are covered too.
import Testing
import Foundation
@testable import Domain

@Suite struct FIXH_CodableClampTests {
    private func announcements(_ seconds: String, items: String = #"[{"assetID":"6F1E6B2A-1B6C-4B66-9C73-0F6D6D2B0A01","name":"a.png","kind":"image"},{"assetID":"6F1E6B2A-1B6C-4B66-9C73-0F6D6D2B0A02","name":"b.png","kind":"image"}]"#) throws -> AnnouncementsSpec {
        let json = #"{"label":"Loop","items":\#(items)\#(seconds.isEmpty ? "" : #","secondsPerPicture":\#(seconds)"#)}"#
        return try JSONDecoder().decode(AnnouncementsSpec.self, from: Data(json.utf8))
    }

    @Test func zeroNegativeAndHugeSecondsAreClampedWhenDecoded() throws {
        #expect(try announcements("0").secondsPerPicture == AnnouncementsSpec.pictureSeconds.lowerBound)
        #expect(try announcements("-40").secondsPerPicture == AnnouncementsSpec.pictureSeconds.lowerBound)
        #expect(try announcements("99999999999").secondsPerPicture == AnnouncementsSpec.pictureSeconds.upperBound)
        #expect(try announcements("17").secondsPerPicture == 17)
        #expect(try announcements("").secondsPerPicture == 8)                         // missing: the same default as a new loop
    }

    @Test func aSoundInDecodedItemsIsDroppedLikeTheInitialiserDoes() throws {
        let spec = try announcements("10", items: #"[{"assetID":"6F1E6B2A-1B6C-4B66-9C73-0F6D6D2B0A01","name":"a.png","kind":"image"},{"assetID":"6F1E6B2A-1B6C-4B66-9C73-0F6D6D2B0A03","name":"s.m4a","kind":"audio"}]"#)
        #expect(spec.items.map(\.name) == ["a.png"])
    }

    @Test func aStoredLoopWithZeroSecondsReadsBackClampedAndTheIndexIsSafe() throws {
        let payload = #"{"label":"Loop","items":[{"assetID":"6F1E6B2A-1B6C-4B66-9C73-0F6D6D2B0A01","name":"a.png","kind":"image"},{"assetID":"6F1E6B2A-1B6C-4B66-9C73-0F6D6D2B0A02","name":"b.png","kind":"image"}],"secondsPerPicture":0}"#
        guard case .announcements(let spec) = PlaylistItemKind(storedKind: "announcements", payload: payload) else { Issue.record("not a loop"); return }
        #expect(spec.secondsPerPicture == 3)
        #expect(spec.pictureIndex(afterSeconds: 7) == 2 % 2)
    }

    @Test func theIndexNeverTrapsOnOddElapsedValues() throws {
        let spec = try announcements("10")
        for elapsed in [0.0, -5, .nan, .infinity, -.infinity, 1e300, Double(Int.max), 1e18, 12.5] {
            let index = spec.pictureIndex(afterSeconds: elapsed)
            #expect((0..<2).contains(index), "elapsed \(elapsed)")
        }
        #expect(spec.pictureIndex(afterSeconds: 25) == 0 && spec.pictureIndex(afterSeconds: 15) == 1)
    }

    @Test func aTextPropSpecIsClampedAndTolerantWhenDecoded() throws {
        func decode(_ json: String) throws -> TextPropSpec { try JSONDecoder().decode(TextPropSpec.self, from: Data(json.utf8)) }
        #expect(try decode(##"{"text":"Hi","fontSize":0,"colorHex":"#FFFFFF","anchor":"center"}"##).fontSize == TextPropSpec.fontSizes.lowerBound)
        #expect(try decode(##"{"text":"Hi","fontSize":1e9,"colorHex":"#FFFFFF","anchor":"center"}"##).fontSize == TextPropSpec.fontSizes.upperBound)
        let odd = try decode(#"{"text":"Hi","fontSize":-3,"colorHex":"nonsense","anchor":"from-a-newer-build"}"#)
        #expect(odd.fontSize == TextPropSpec.fontSizes.lowerBound && odd.anchor == .bottomLeft)
        #expect(odd.color == .white)                                                  // an unreadable colour already read as white
        #expect(try decode(#"{"text":"Hi"}"#).fontSize == 48)                          // missing values take the initialiser's defaults
    }

    @Test func aPropWithAnOutOfRangeOpacityIsClampedWhenDecoded() throws {
        func prop(_ opacity: String) throws -> Prop {
            let json = #"{"id":"6F1E6B2A-1B6C-4B66-9C73-0F6D6D2B0A09","name":"Logo","imagePath":"/x.png","frame":{"x":0,"y":0,"width":1,"height":1},"opacity":\#(opacity),"isOn":true}"#
            return try JSONDecoder().decode(Prop.self, from: Data(json.utf8))
        }
        #expect(try prop("7").opacity == 1 && prop("-2").opacity == 0 && prop("0.4").opacity == 0.4)
        #expect(Prop(name: "x", imagePath: "", frame: .full, opacity: .nan).opacity == 1)
    }
}
