// LIB-004b: reading a translation from disk for `import`: a LIB-004 JSON file, one USFM file, or a folder of USFM files.
import Foundation
import ScriptureEngine

struct FileSourceResult {
    var file: TranslationFile
    /// Things the operator should see: skipped files, USFM warnings.
    var notes: [String]
}

enum FileSourceError: Error, Equatable {
    case message(String)
    var text: String { if case .message(let text) = self { return text } else { return "" } }
}

enum TranslationFileSource {
    static let usfmExtensions: Set<String> = ["usfm", "sfm", "ptx"]

    /// - Parameter metadata: used for USFM only (a JSON file carries its own); `language` and an id are then required.
    static func load(path: String, metadata: ExportMetadata) throws -> FileSourceResult {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw FileSourceError.message("the file or folder “\(path)” does not exist.")
        }
        if isDirectory.boolValue { return try loadUSFM(files: usfmFiles(in: path), metadata: metadata, origin: "folder") }
        let url = URL(fileURLWithPath: path)
        if usfmExtensions.contains(url.pathExtension.lowercased()) { return try loadUSFM(files: [path], metadata: metadata, origin: "file") }
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw FileSourceError.message("could not read “\(path)”: \(error.localizedDescription)") }
        let leading = data.prefix(64).first { !$0.isASCIIWhitespace && $0 != 0xEF && $0 != 0xBB && $0 != 0xBF }
        guard leading == UInt8(ascii: "{") else {
            throw FileSourceError.message("“\(url.lastPathComponent)” is not a translation file: expected .json, .usfm or a folder of .usfm files.")
        }
        do {
            return FileSourceResult(file: try TranslationLoader.decode(from: data), notes: [])
        } catch let error as TranslationLoadError {
            throw FileSourceError.message(error.message)
        }
    }

    static func usfmFiles(in folder: String) throws -> [String] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: folder) else {
            throw FileSourceError.message("could not list the folder “\(folder)”.")
        }
        let files = names.filter { usfmExtensions.contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix(".") }.sorted()
        guard !files.isEmpty else { throw FileSourceError.message("the folder “\(folder)” has no .usfm files.") }
        return files.map { (folder as NSString).appendingPathComponent($0) }
    }

    private static func loadUSFM(files: [String], metadata: ExportMetadata, origin: String) throws -> FileSourceResult {
        guard let language = metadata.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty else {
            throw FileSourceError.message("--language is required for USFM (a USFM \(origin) does not say which language it is in; for example --language en).")
        }
        guard let id = metadata.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            throw FileSourceError.message("--id is required for USFM: the short code the library will know this translation by (for example --id web).")
        }
        let meta = TranslationMetadata(
            id: id,
            name: nonEmpty(metadata.name) ?? id,
            language: language,
            abbreviation: nonEmpty(metadata.abbreviation) ?? id,
            copyright: nonEmpty(metadata.copyright) ?? TranslationExporter.notStated,
            license: nonEmpty(metadata.licence) ?? TranslationExporter.notStated,
            sourceURL: nonEmpty(metadata.source),
            isPublicDomain: metadata.isPublicDomain,
            versification: nonEmpty(metadata.versification),
            ownerApproval: metadata.ownerApproved ? OwnerApproval(approved: true, date: nonEmpty(metadata.ownerApprovalDate), note: nonEmpty(metadata.ownerApprovalNote)) : nil)
        var file = TranslationFile(metadata: meta, books: [:])
        var notes: [String] = []
        var seen = Set<BookID>()
        for path in files {
            let name = (path as NSString).lastPathComponent
            guard let data = FileManager.default.contents(atPath: path) else { notes.append("\(name): could not be read; skipped."); continue }
            var text = String(decoding: data, as: UTF8.self)
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            let result = USFMImporter.importBook(text)
            guard let book = result.book else {
                notes.append("\(name): not one of the 66 books (no usable \\id line); skipped.")
                continue
            }
            guard seen.insert(book).inserted else { notes.append("\(name): a second file for \(book.rawValue); skipped."); continue }
            file.setBook(book, chapters: result.chapters)
            for warning in result.report.warnings { notes.append("\(name): \(warning)") }
            if !result.report.duplicateVerses.isEmpty { notes.append("\(name): \(result.report.duplicateVerses.count) verses appear twice; the first was kept.") }
            if !result.report.bridgedVerses.isEmpty { notes.append("\(name): \(result.report.bridgedVerses.count) verse bridges (such as \(result.report.bridgedVerses[0])) stored at their first number.") }
        }
        guard !seen.isEmpty else { throw FileSourceError.message("none of the \(files.count) USFM file(s) is one of the 66 books.") }
        return FileSourceResult(file: file, notes: notes)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private extension UInt8 {
    var isASCIIWhitespace: Bool { self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D }
}
