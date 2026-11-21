// FIX-D S5: what a bundle must not carry: the card's persistent id, a photo's metadata (location, camera, date), the path or
// name of a file the tester chose, and names that identify a person or a Mac. A photo is decoded and written again, so only
// the picture survives.
import Testing
import Foundation
import ImageIO
import CoreGraphics
import SDIEngine
@testable import OutputEngine

/// Writes a small JPEG with the metadata a phone writes: where, with what, when.
enum TestPhoto {
    static func write(to url: URL, withLocation: Bool = true, orientation: Int = 1) throws {
        let w = 64, h = 32
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
        ctx.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        guard let image = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        var props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "PastorPhone", kCGImagePropertyTIFFModel: "Model 7"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:15 09:41:00", kCGImagePropertyExifUserComment: "Smith wedding"],
            kCGImagePropertyOrientation: orientation,
        ]
        if withLocation {
            props[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 37.7749, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4194, kCGImagePropertyGPSLongitudeRef: "W",
            ]
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        try (data as Data).write(to: url)
    }

    /// The metadata dictionaries a file carries.
    static func metadata(of data: Data) -> [String: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return [:] }
        return props
    }

    static func pixelSize(of data: Data) -> (Int, Int)? {
        let p = metadata(of: data)
        guard let w = p[kCGImagePropertyPixelWidth as String] as? Int, let h = p[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
        return (w, h)
    }
}

extension HWTEST_Heavy {
@Suite struct FIXD_S5_PrivacyTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixd-priv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func everyFile(in zip: URL) throws -> [(name: String, data: Data)] { try HardwareTestZip.read(from: zip) }

    // MARK: the card's id

    @Test func theCardsPersistentIdIsReplacedByAShortHash() async {
        let report = await runSteps([.environment, .devices])
        #expect(report.deviceID != nil)
        #expect(report.deviceID != HardwareTestRig.simulatedDeviceID)
        #expect(report.deviceID?.count == 8)
        #expect(report.deviceID?.allSatisfy { $0.isHexDigit } == true)
    }

    // MARK: the photo

    @Test func aPhotoIsReEncodedWithoutItsMetadataUnderANeutralName() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("Smith wedding IMG_0042.JPG")
        try TestPhoto.write(to: photo)
        let original = try Data(contentsOf: photo)
        #expect(TestPhoto.metadata(of: original)[kCGImagePropertyGPSDictionary as String] != nil)       // the fixture really has a location
        let writer = try HardwareTestBundleWriter(directory: dir.appendingPathComponent("work"))
        let name = try writer.attachPhoto(from: photo)
        #expect(name == "photos/photo-1.jpg")
        let zip = dir.appendingPathComponent("out.zip")
        try writer.finish(report: HWTestSamples.report(), log: "", zipTo: zip)
        let entry = try #require(try everyFile(in: zip).first { $0.name == name })
        let meta = TestPhoto.metadata(of: entry.data)
        #expect(meta[kCGImagePropertyGPSDictionary as String] == nil, "location survived: \(meta)")
        let exif = meta[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] == nil && exif?[kCGImagePropertyExifUserComment as String] == nil, "\(String(describing: exif))")
        let tiff = meta[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake as String] == nil && tiff?[kCGImagePropertyTIFFModel as String] == nil, "\(String(describing: tiff))")
        let raw = String(decoding: entry.data, as: UTF8.self)
        #expect(!raw.contains("PastorPhone") && !raw.contains("Smith"))
        // the picture is still there
        let size = try #require(TestPhoto.pixelSize(of: entry.data))
        #expect(size.0 == 64 && size.1 == 32)
        // and nothing in the bundle holds the original name
        for e in try everyFile(in: zip) { #expect(!String(decoding: e.data, as: UTF8.self).contains("IMG_0042"), "\(e.name)") }
    }

    @Test func aPhotoTurnedOnItsSideIsMadeUprightBecauseTheOrientationTagIsNotKept() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("turned.jpg")
        try TestPhoto.write(to: photo, withLocation: false, orientation: 6)        // "rotate 90 degrees": the file is 64 x 32, the picture 32 x 64
        let writer = try HardwareTestBundleWriter(directory: dir.appendingPathComponent("work"))
        let name = try writer.attachPhoto(from: photo)
        let size = try #require(TestPhoto.pixelSize(of: try Data(contentsOf: dir.appendingPathComponent("work/\(name)"))))
        #expect(size.0 == 32 && size.1 == 64, "\(size)")
    }

    @Test func aFileThatIsNotAPictureIsRefusedNotCopied() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let notAPhoto = dir.appendingPathComponent("secret-notes.jpg")
        try Data("Dear pastor, the key is under the mat".utf8).write(to: notAPhoto)
        let writer = try HardwareTestBundleWriter(directory: dir.appendingPathComponent("work"))
        do { _ = try writer.attachPhoto(from: notAPhoto); Issue.record("an unreadable file must not be attached") } catch {
            #expect(!error.localizedDescription.contains("secret-notes"), "\(error.localizedDescription)")
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("work/photos").path))
    }

    // MARK: a whole run

    @Test func aRunWithAPhotoOnAnotherVolumeLeavesNeitherItsPathNorItsNameNorItsLocationInTheBundle() async throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        // one photo that exists (with a location), one on a volume that is not there: both are named in the answers
        let real = dir.appendingPathComponent("Pastor Bob sermon IMG_7777.jpg")
        try TestPhoto.write(to: real)
        let gone = "/Volumes/CHURCH-USB-STICK/Pastor Bob/Private/IMG_4242 (copy).jpg"
        final class Picks: @unchecked Sendable { let lock = NSLock(); var n = 0; func next() -> Int { lock.withLock { n += 1; return n } } }
        let picks = Picks()
        let tester = ScriptedInteraction { [real] p in
            switch p.kind {
            case .photo: return picks.next() == 1 ? .attachment(real.path) : .attachment(gone)
            case .humanBars, .humanKeyEdges: return .yes
            default: return .proceed
            }
        }
        var config = HardwareTestConfiguration.tiny
        config.includeHumanChecks = true
        let writer = try HardwareTestBundleWriter(directory: dir.appendingPathComponent("work"))
        let rig = HardwareTestRig.simulated()
        let runner = HardwareTestRunner(provider: rig.provider, configuration: config, clock: rig.clock, interaction: tester, environment: .fixed,
                                        resources: FixedResources.probe, bundle: HardwareTestBundleTarget(writer: writer, zipURL: dir.appendingPathComponent("o.zip")),
                                        steps: HardwareTestSteps.standard(config).filter { $0.id == .humanChecks })
        let result = await runner.run()
        let zip = try #require(result.bundleURL)
        let step = result.report.step(.humanChecks)
        #expect(step.value("Photo 1") == "photos/photo-1.jpg")
        for entry in try everyFile(in: zip) {
            let text = String(decoding: entry.data, as: UTF8.self)
            for leak in ["CHURCH-USB", "IMG_4242", "IMG_7777", "Pastor Bob", "/Volumes/"] {
                #expect(!text.contains(leak), "\(leak) in \(entry.name)")
            }
            if entry.name.hasPrefix("photos/") { #expect(TestPhoto.metadata(of: entry.data)[kCGImagePropertyGPSDictionary as String] == nil) }
        }
        let log = try #require(try everyFile(in: zip).first { $0.name == "engine-log.txt" })
        #expect(String(decoding: log.data, as: UTF8.self).contains("Answer: a photo was chosen"))
    }
}
}
