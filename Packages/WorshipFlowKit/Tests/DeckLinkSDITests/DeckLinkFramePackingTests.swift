// HW-003: BGRA frames into a card's buffer: row order, row stride padding and un-premultiplying, tested against a fake
// buffer. Verification level: Unit Tested. The SDK's own buffer is only ever touched on a real card.
import DeckLinkC
import Foundation
import SDIEngine
import Testing
@testable import DeckLinkSDI

@Suite struct HW003_FramePackingTests {
    /// 3x2 picture, every byte distinct so a misplaced byte shows.
    private let width = 3
    private let height = 2
    private var picture: [UInt8] { (0..<(3 * 2 * 4)).map { UInt8($0 + 1) } }

    @Test func rowsLandTopRowFirstWithTheCardsStride() throws {
        let stride = 16     // 4 bytes of padding per row beyond width*4 = 12
        var fake = [UInt8](repeating: 0xEE, count: stride * height)
        let ok = fake.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: picture, width: width, height: height, into: $0, destinationRowBytes: stride) }
        #expect(ok)
        #expect(Array(fake[0..<12]) == Array(picture[0..<12]), "row 0 must be the top row, at offset 0")
        #expect(Array(fake[16..<28]) == Array(picture[12..<24]), "row 1 starts at the card's stride")
    }

    @Test func paddingBytesAreLeftAlone() {
        let stride = 16
        var fake = [UInt8](repeating: 0xEE, count: stride * height)
        _ = fake.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: picture, width: width, height: height, into: $0, destinationRowBytes: stride) }
        #expect(Array(fake[12..<16]) == [0xEE, 0xEE, 0xEE, 0xEE])
        #expect(Array(fake[28..<32]) == [0xEE, 0xEE, 0xEE, 0xEE])
    }

    @Test func aTightStrideCopiesStraightThrough() {
        var fake = [UInt8](repeating: 0, count: 12 * height)
        let ok = fake.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: picture, width: width, height: height, into: $0, destinationRowBytes: 12) }
        #expect(ok)
        #expect(fake == picture)
    }

    @Test func impossibleArgumentsWriteNothing() {
        var fake = [UInt8](repeating: 0xEE, count: 64)
        let short = fake.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: picture, width: width, height: height, into: $0, destinationRowBytes: 8) }
        #expect(!short, "a stride smaller than a row must be refused")
        let wrongSize = fake.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: [1, 2, 3], width: width, height: height, into: $0, destinationRowBytes: 12) }
        #expect(!wrongSize)
        let tooSmallBuffer = fake.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: picture, width: width, height: height, into: UnsafeMutableRawBufferPointer(rebasing: $0[0..<20]), destinationRowBytes: 16) }
        #expect(!tooSmallBuffer)
        #expect(fake.allSatisfy { $0 == 0xEE })
    }

    @Test func theCFunctionRefusesNullAndZero() {
        var out = [UInt8](repeating: 0, count: 16)
        let src = [UInt8](repeating: 1, count: 16)
        #expect(!DLBPackBGRA(nil, 8, 2, 2, &out, 8, .premultiplied))
        #expect(!src.withUnsafeBufferPointer { DLBPackBGRA($0.baseAddress, 8, 0, 2, &out, 8, .premultiplied) })
        #expect(!src.withUnsafeBufferPointer { DLBPackBGRA($0.baseAddress, 8, 2, 2, nil, 8, .premultiplied) })
    }

    // MARK: un-premultiplying for straight-alpha keyed output

    @Test func straightAlphaDividesColourByAlphaAndKeepsAlpha() {
        // BGRA: half-covered red (premultiplied 0,0,128, alpha 128), fully opaque blue, fully transparent, quarter green.
        let src: [UInt8] = [0, 0, 128, 128,   255, 0, 0, 255,   0, 0, 0, 0,   0, 32, 0, 64]
        var out = [UInt8](repeating: 0xEE, count: 16)
        let ok = out.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: src, width: 4, height: 1, into: $0, destinationRowBytes: 16, straightAlpha: true) }
        #expect(ok)
        #expect(Array(out[0..<4]) == [0, 0, 255, 128])
        #expect(Array(out[4..<8]) == [255, 0, 0, 255])
        #expect(Array(out[8..<12]) == [0, 0, 0, 0])
        #expect(Array(out[12..<16]) == [0, 128, 0, 64])
    }

    @Test func straightAlphaAgreesWithTheFillKeySplitterEverywhere() {
        // Same rounding as SDIEngine's splitter, so keyed output matches what the engine's tests describe.
        var src: [UInt8] = []
        for a in stride(from: 0, through: 255, by: 15) { for c in stride(from: 0, through: Int(a), by: 17) { src += [UInt8(c), UInt8(c / 2), UInt8(min(a, c + 3)), UInt8(a)] } }
        let pixels = src.count / 4
        var out = [UInt8](repeating: 0, count: src.count)
        let ok = out.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: src, width: pixels, height: 1, into: $0, destinationRowBytes: pixels * 4, straightAlpha: true) }
        #expect(ok)
        let fill = FillKeySplitter.split(bgra: src, fillAlphaMode: .straight).fill
        for i in 0..<pixels {
            #expect(Array(out[i * 4..<i * 4 + 3]) == Array(fill[i * 4..<i * 4 + 3]), "pixel \(i) colour")
            #expect(out[i * 4 + 3] == src[i * 4 + 3], "pixel \(i) alpha is kept")
        }
    }

    @Test func premultipliedModeLeavesColourUntouched() {
        let src: [UInt8] = [0, 0, 128, 128]
        var out = [UInt8](repeating: 0, count: 4)
        _ = out.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: src, width: 1, height: 1, into: $0, destinationRowBytes: 4) }
        #expect(out == src)
    }

    // MARK: the reverse direction, for captured frames

    @Test func capturedRowsAreTightenedAndPaddingDropped() throws {
        let stride = 16
        var card = [UInt8](repeating: 0xEE, count: stride * height)
        card.replaceSubrange(0..<12, with: picture[0..<12])
        card.replaceSubrange(16..<28, with: picture[12..<24])
        let tight = try card.withUnsafeBytes { try #require(DeckLinkFramePacking.tightBGRA(from: $0, width: width, height: height, rowBytes: stride)) }
        #expect(tight == picture)
    }

    @Test func aCapturedBufferThatIsTooSmallIsRefused() {
        let bytes = [UInt8](repeating: 0, count: 20)
        bytes.withUnsafeBytes {
            #expect(DeckLinkFramePacking.tightBGRA(from: $0, width: 3, height: 2, rowBytes: 16) == nil)
            #expect(DeckLinkFramePacking.tightBGRA(from: $0, width: 3, height: 2, rowBytes: 8) == nil)
            #expect(DeckLinkFramePacking.tightBGRA(from: $0, width: 0, height: 2, rowBytes: 16) == nil)
        }
    }

    @Test func aFullHDFrameWithCardPaddingRoundTrips() throws {
        let w = 1920, h = 1080, rowStride = 7680 + 64
        var source = [UInt8](repeating: 0, count: w * h * 4)
        for i in stride(from: 0, to: source.count, by: 4) { source[i] = UInt8(truncatingIfNeeded: i / 4); source[i + 3] = 255 }
        var card = [UInt8](repeating: 0xAA, count: rowStride * h)
        let ok = card.withUnsafeMutableBytes { DeckLinkFramePacking.pack(bgra: source, width: w, height: h, into: $0, destinationRowBytes: rowStride) }
        #expect(ok)
        let back = try card.withUnsafeBytes { try #require(DeckLinkFramePacking.tightBGRA(from: $0, width: w, height: h, rowBytes: rowStride)) }
        #expect(back == source)
    }
}
