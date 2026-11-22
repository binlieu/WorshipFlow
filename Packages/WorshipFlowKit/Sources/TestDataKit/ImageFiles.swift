// TESTDATA-001: the background pictures under TestData/backgrounds, as media-bin entries.
import Foundation
import Persistence

public enum ImageFiles {
    /// `solid` then `gradient`, each sorted by file name. The bin keeps the absolute path, so the folder must stay where it is.
    public static func specs(testData: URL) throws -> [LibraryStore.MediaAssetSpec] {
        var result: [LibraryStore.MediaAssetSpec] = []
        for kind in ["solid", "gradient"] {
            let folder = testData.appendingPathComponent("backgrounds/\(kind)", isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names.filter({ $0.hasSuffix(".png") && !$0.hasPrefix(".") }).sorted() {
                let url = folder.appendingPathComponent(name)
                let size = pngSize(url)
                result.append(.init(name: String(name.dropLast(".png".count)), kind: .image, path: url.path,
                                    pixelWidth: size?.width, pixelHeight: size?.height))
            }
        }
        return result
    }

    /// Width and height from the PNG header (the IHDR chunk), or nil when the file is not a PNG.
    static func pngSize(_ url: URL) -> (width: Int, height: Int)? {
        guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 24) else { return nil }
        try? handle.close()
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let b = [UInt8](head)
        guard b.count == 24, Array(b[0..<8]) == signature else { return nil }
        func be(_ i: Int) -> Int { Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3]) }
        return (be(16), be(20))
    }
}
