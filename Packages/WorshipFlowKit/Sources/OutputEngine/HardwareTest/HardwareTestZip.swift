// HWTEST-001: a minimal zip writer and reader (stored entries, no compression, no zip64). The bundle is small text
// and a few photos that are already compressed, and a plain format with a CRC check can be opened by anything
// (Finder, `unzip`) and read by the coordinator's tools without this app.
import Foundation

public enum HardwareTestZipError: Error, LocalizedError, Equatable {
    case notAZip
    case unsupported(String)
    case corrupt(String)
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .notAZip: return "The file is not a zip archive."
        case .unsupported(let what): return "The zip uses something this reader does not support: \(what)."
        case .corrupt(let name): return "The zip is damaged: \(name) does not match its checksum."
        case .tooLarge: return "The bundle is too large for a plain zip file."
        }
    }
}

public enum HardwareTestZip {
    public static func write(_ entries: [(name: String, data: Data)], to url: URL) throws {
        var out = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            guard entry.data.count < 0xFFFF_FFFF, out.count < 0xFFFF_FFFF, entries.count < 0xFFFF else { throw HardwareTestZipError.tooLarge }
            let offset = UInt32(out.count)
            out.appendLE(UInt32(0x04034b50)); out.appendLE(UInt16(20)); out.appendLE(UInt16(0x0800)); out.appendLE(UInt16(0))
            out.appendLE(UInt16(0)); out.appendLE(UInt16(0x0021))              // 1980-01-01 00:00: a fixed date, so the same content gives the same file
            out.appendLE(crc); out.appendLE(UInt32(entry.data.count)); out.appendLE(UInt32(entry.data.count))
            out.appendLE(UInt16(name.count)); out.appendLE(UInt16(0))
            out.append(name); out.append(entry.data)

            central.appendLE(UInt32(0x02014b50)); central.appendLE(UInt16(20)); central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0x0021))
            central.appendLE(crc); central.appendLE(UInt32(entry.data.count)); central.appendLE(UInt32(entry.data.count))
            central.appendLE(UInt16(name.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0)); central.appendLE(offset)
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.appendLE(UInt32(0x06054b50)); out.appendLE(UInt16(0)); out.appendLE(UInt16(0))
        out.appendLE(UInt16(entries.count)); out.appendLE(UInt16(entries.count))
        out.appendLE(UInt32(central.count)); out.appendLE(centralOffset); out.appendLE(UInt16(0))
        try out.write(to: url, options: .atomic)
    }

    /// Reads a zip whose entries are stored (as `write` makes them). Every entry's checksum is verified.
    public static func read(from url: URL) throws -> [(name: String, data: Data)] {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw HardwareTestZipError.notAZip }
        var end = bytes.count - 22
        while end >= 0, le32(bytes, end) != 0x06054b50 { end -= 1 }
        guard end >= 0 else { throw HardwareTestZipError.notAZip }
        let count = Int(le16(bytes, end + 10))
        var pos = Int(le32(bytes, end + 16))
        var result: [(name: String, data: Data)] = []
        for _ in 0..<count {
            guard pos + 46 <= bytes.count, le32(bytes, pos) == 0x02014b50 else { throw HardwareTestZipError.notAZip }
            let method = le16(bytes, pos + 10)
            let crc = le32(bytes, pos + 16)
            let size = Int(le32(bytes, pos + 24))
            let nameLength = Int(le16(bytes, pos + 28)), extra = Int(le16(bytes, pos + 30)), comment = Int(le16(bytes, pos + 32))
            let local = Int(le32(bytes, pos + 42))
            guard pos + 46 + nameLength <= bytes.count else { throw HardwareTestZipError.notAZip }
            let name = String(decoding: bytes[(pos + 46)..<(pos + 46 + nameLength)], as: UTF8.self)
            guard method == 0 else { throw HardwareTestZipError.unsupported("compressed entry \(name)") }
            guard local + 30 <= bytes.count, le32(bytes, local) == 0x04034b50 else { throw HardwareTestZipError.notAZip }
            let start = local + 30 + Int(le16(bytes, local + 26)) + Int(le16(bytes, local + 28))
            guard start + size <= bytes.count else { throw HardwareTestZipError.notAZip }
            let body = data.subdata(in: start..<(start + size))
            guard crc32(body) == crc else { throw HardwareTestZipError.corrupt(name) }
            result.append((name, body))
            pos += 46 + nameLength + extra + comment
        }
        return result
    }

    private static func le16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
    private static func le32(_ b: [UInt8], _ i: Int) -> UInt32 { UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        crcTable.withUnsafeBufferPointer { table in
            data.withUnsafeBytes { raw in
                for byte in raw.bindMemory(to: UInt8.self) { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
            }
        }
        return c ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func appendLE(_ v: UInt16) { append(UInt8(v & 255)); append(UInt8(v >> 8)) }
    mutating func appendLE(_ v: UInt32) { appendLE(UInt16(v & 0xFFFF)); appendLE(UInt16(v >> 16)) }
}
