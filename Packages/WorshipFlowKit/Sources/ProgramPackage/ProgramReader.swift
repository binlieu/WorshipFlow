// LIB-005 item 4: reading a package is reading untrusted input. `open` checks everything it can without writing anything:
// the manifest's size and format, every path it names, and that each listed file is a plain file inside the package.
import Foundation
import Domain

extension ProgramPackageContents {
    /// Reads and checks a package. Throws for anything unsafe or unreadable; writes nothing.
    public static func open(_ url: URL) throws -> ProgramPackageContents {
        let fm = FileManager.default
        var isFolder: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw ProgramPackageError.notAProgramPackage("it is not a folder package.")
        }
        // The package folder itself may be reached through a link (an alias on a USB stick); everything inside it may not.
        let root = url.resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = root.appendingPathComponent(ProgramFormat.manifestName)
        guard let manifestInfo = ProgramFiles.lstatInfo(manifestURL) else {
            throw ProgramPackageError.notAProgramPackage("\(ProgramFormat.manifestName) is missing.")
        }
        guard !manifestInfo.isSymlink else { throw ProgramPackageError.linkNotAllowed(ProgramFormat.manifestName) }
        guard manifestInfo.isRegular else { throw ProgramPackageError.notAProgramPackage("\(ProgramFormat.manifestName) is not a file.") }
        guard manifestInfo.size <= Int64(ProgramFormat.maxManifestBytes) else {
            throw ProgramPackageError.manifestTooLarge(Int(clamping: manifestInfo.size))
        }
        let data: Data
        do { data = try Data(contentsOf: manifestURL) }
        catch { throw ProgramPackageError.manifestUnreadable("\(ProgramFormat.manifestName) could not be opened.") }

        struct Header: Decodable { var format: String?; var formatVersion: Int? }
        let header: Header
        do { header = try JSONDecoder().decode(Header.self, from: data) }
        catch { throw ProgramPackageError.manifestUnreadable("\(ProgramFormat.manifestName) is not valid JSON.") }
        guard header.format == ProgramFormat.name else {
            throw ProgramPackageError.notAProgramPackage("\(ProgramFormat.manifestName) does not describe a WORSHIPFLOW program.")
        }
        guard let version = header.formatVersion, version >= 1 else {
            throw ProgramPackageError.notAProgramPackage("its format version is missing or not valid.")
        }
        guard version <= ProgramFormat.version else {
            throw ProgramPackageError.newerFormat(found: version, supported: ProgramFormat.version)
        }
        let document: ProgramDocument
        do { document = try JSONDecoder().decode(ProgramDocument.self, from: data) }
        catch { throw ProgramPackageError.manifestUnreadable("Something in it is missing or has the wrong shape.") }

        try validate(document)
        let files = try checkFiles(of: document, in: root)
        return ProgramPackageContents(url: root, document: document, files: files)
    }

    /// Every path the document names must be a safe package path that the media list covers, and the list must be sane.
    private static func validate(_ document: ProgramDocument) throws {
        guard document.media.count <= ProgramFormat.maxMediaFiles else { throw ProgramPackageError.tooManyFiles(document.media.count) }
        var listed: Set<String> = []
        for entry in document.media {
            guard ProgramPathRules.isSafePackagePath(entry.file) else { throw ProgramPackageError.unsafePath(describe(entry.file)) }
            guard listed.insert(entry.file).inserted else { throw ProgramPackageError.unsafePath(describe(entry.file)) }
            if entry.status == .included {
                guard let sha = entry.sha256, sha.count == 64, sha.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
                    throw ProgramPackageError.manifestUnreadable("A media entry has no valid checksum.")
                }
            }
        }
        var referenced: [String] = document.mediaAssets.map(\.file)
        for theme in document.themes { if case .image(let path) = theme.background { referenced.append(path) } }
        for slide in document.presentations.flatMap(\.slides) {
            for object in slide.objects { if case .image(let image) = object.content { referenced.append(image.path) } }
        }
        for path in referenced {
            guard ProgramPathRules.isSafePackagePath(path) else { throw ProgramPackageError.unsafePath(describe(path)) }
            guard listed.contains(path) else { throw ProgramPackageError.packageFileMissing(describe(path)) }
        }
    }

    /// Each included file must exist, be a plain file (not a link) and lie inside the package. Returns their sizes.
    private static func checkFiles(of document: ProgramDocument, in root: URL) throws -> [String: Int64] {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var sizes: [String: Int64] = [:]
        for entry in document.media where entry.status == .included {
            let file = root.appendingPathComponent(entry.file)
            guard let info = ProgramFiles.lstatInfo(file) else { throw ProgramPackageError.packageFileMissing(entry.file) }
            guard !info.isSymlink else { throw ProgramPackageError.linkNotAllowed(entry.file) }
            guard info.isRegular else { throw ProgramPackageError.unsafePath(describe(entry.file)) }
            // A folder on the way may be a link that leads out.
            let real = file.resolvingSymlinksInPath().standardizedFileURL.path
            guard real.hasPrefix(rootPath) else { throw ProgramPackageError.linkNotAllowed(entry.file) }
            sizes[entry.file] = info.size
        }
        return sizes
    }

    private static func describe(_ path: String) -> String {
        let cleaned = String(path.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }.map(Character.init))
        return cleaned.count > 80 ? String(cleaned.prefix(80)) + "…" : cleaned
    }
}
