// MEDIA-01: probing and thumbnails.
import Testing
import Foundation
import CoreGraphics
import Domain
@testable import MediaEngine

@Suite struct MediaProbeTests {
    @Test func probesAMovie() async throws {
        let dir = try TestMedia.tempDirectory()
        let url = dir.appendingPathComponent("clip.mov")
        try await TestMedia.writeMovie(to: url, width: 64, height: 48, segments: [(2, TestMedia.red)])
        let info = try await MediaProbe.probe(url: url)
        #expect(info.kind == .video && info.pixelWidth == 64 && info.pixelHeight == 48 && info.hasAudio == false)
        #expect(abs((info.duration ?? 0) - 2) < 0.2)
    }

    @Test func probesAPicture() async throws {
        let dir = try TestMedia.tempDirectory()
        let url = dir.appendingPathComponent("still.png")
        try TestMedia.writePNG(to: url, width: 200, height: 100, red: 10, green: 200, blue: 30)
        let info = try await MediaProbe.probe(url: url)
        #expect(info == MediaInfo(kind: .image, duration: nil, pixelWidth: 200, pixelHeight: 100, hasAudio: false))
    }

    @Test func probesASound() async throws {
        let dir = try TestMedia.tempDirectory()
        let url = dir.appendingPathComponent("tone.caf")
        try TestMedia.writeSound(to: url, seconds: 1)
        let info = try await MediaProbe.probe(url: url)
        #expect(info.kind == .audio && info.hasAudio && info.pixelWidth == nil)
        #expect(abs((info.duration ?? 0) - 1) < 0.1)
    }

    @Test func missingAndUnreadableFilesGiveClearErrors() async throws {
        let dir = try TestMedia.tempDirectory()
        let missing = dir.appendingPathComponent("nope.mov")
        await #expect(throws: MediaProbeError.fileNotFound(missing.path)) { try await MediaProbe.probe(url: missing) }

        let text = dir.appendingPathComponent("notes.mov")
        try "this is not a movie".write(to: text, atomically: true, encoding: .utf8)
        await #expect(throws: MediaProbeError.unsupported(text.path)) { try await MediaProbe.probe(url: text) }

        await #expect(throws: MediaProbeError.fileNotFound(dir.path)) { try await MediaProbe.probe(url: dir) }
        #expect(MediaProbeError.unsupported("x").errorDescription?.isEmpty == false)
    }
}

@Suite struct MediaThumbnailerTests {
    @Test func stillIsDownsizedKeepingItsShape() async throws {
        let dir = try TestMedia.tempDirectory()
        let url = dir.appendingPathComponent("wide.png")
        try TestMedia.writePNG(to: url, width: 400, height: 200, red: 200, green: 20, blue: 20)
        let image = try await MediaThumbnailer.thumbnail(url: url, kind: .image, maxPixelSize: 100)
        #expect(image.width == 100 && image.height == 50)
    }

    @Test func posterSkipsABlackOpening() async throws {
        let dir = try TestMedia.tempDirectory()
        let url = dir.appendingPathComponent("fade-in.mov")
        // 10 % of 5 s is 0.5 s, which is still black; the poster must come from a later, lit frame.
        try await TestMedia.writeMovie(to: url, segments: [(0.8, TestMedia.black), (4.2, TestMedia.green)])
        let image = try await MediaThumbnailer.thumbnail(url: url, kind: .video, maxPixelSize: 32)
        #expect(max(image.width, image.height) <= 32)
        #expect(MediaThumbnailer.isNearlyBlack(image) == false)
    }

    @Test func posterOfAnAllBlackMovieStillComesBack() async throws {
        let dir = try TestMedia.tempDirectory()
        let url = dir.appendingPathComponent("dark.mov")
        try await TestMedia.writeMovie(to: url, segments: [(1, TestMedia.black)])
        let image = try await MediaThumbnailer.thumbnail(url: url, kind: .video)
        #expect(image.width > 0 && MediaThumbnailer.isNearlyBlack(image))
    }

    @Test func badInputsThrow() async throws {
        let dir = try TestMedia.tempDirectory()
        await #expect(throws: MediaProbeError.self) { try await MediaThumbnailer.thumbnail(url: dir.appendingPathComponent("x.png"), kind: .image) }
        let sound = dir.appendingPathComponent("a.caf")
        try TestMedia.writeSound(to: sound, seconds: 0.5)
        await #expect(throws: MediaProbeError.self) { try await MediaThumbnailer.thumbnail(url: sound, kind: .audio) }
    }
}
