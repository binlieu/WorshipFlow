// FIX-AC item C (LIB-004d): the packaging script copies only the allow-listed translation file into the app, and refuses an app that holds more.
// Exercised in a temporary folder through the sourced helper (scripts/lib-bundle-translations.sh); the full packaging script is not run. The files
// are invented bytes: no Bible text is in the repository.
import Testing
import Foundation

@Suite struct FIXAC_BundleScriptTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixac-script-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs `body` (shell text) with the helper sourced; returns the status and the output.
    private func run(_ body: String) throws -> (status: Int32, output: String) {
        let helper = Self.repoRoot.appendingPathComponent("scripts/lib-bundle-translations.sh").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "source '\(helper)'\n\(body)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func names(_ url: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }

    @Test func onlyTheAllowListedFileIsCopiedAndTheCheckPasses() throws {
        let root = try scratch()
        let bibles = root.appendingPathComponent("Bibles"), app = root.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: bibles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        for name in ["KJV.json", "NKJV.json", "kjv.json.bak", "Other.json", "KJV.json.old"] { try Data("invented \(name)".utf8).write(to: bibles.appendingPathComponent(name)) }
        let r = try run("bundle_translations '\(bibles.path)' '\(app.path)' && check_bundled_translations '\(app.path)'")
        #expect(r.status == 0, "\(r.output)")
        #expect(names(app.appendingPathComponent("Contents/Resources/Bibles")) == ["KJV.json"])
        #expect(try Data(contentsOf: app.appendingPathComponent("Contents/Resources/Bibles/KJV.json")) == Data("invented KJV.json".utf8))
    }

    @Test func withoutTheFileTheBuildIsMadeAndOneLineSaysSo() throws {
        let root = try scratch()
        let bibles = root.appendingPathComponent("Bibles"), app = root.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: bibles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("invented".utf8).write(to: bibles.appendingPathComponent("NKJV.json"))           // another file alone is not copied
        let r = try run("bundle_translations '\(bibles.path)' '\(app.path)' && check_bundled_translations '\(app.path)'")
        #expect(r.status == 0 && r.output.split(separator: "\n").count == 1 && r.output.contains("without a bundled translation"), "\(r.output)")
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/Bibles").path))
        let missing = try run("bundle_translations '\(root.path)/no-such-folder' '\(app.path)'")
        #expect(missing.status == 0 && missing.output.contains("without a bundled translation"))
    }

    @Test func aLinkIsNotFollowed() throws {
        let root = try scratch()
        let bibles = root.appendingPathComponent("Bibles"), app = root.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: bibles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let elsewhere = root.appendingPathComponent("elsewhere.json")
        try Data("invented".utf8).write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: bibles.appendingPathComponent("KJV.json"), withDestinationURL: elsewhere)
        let r = try run("bundle_translations '\(bibles.path)' '\(app.path)'")
        #expect(r.status == 0 && !FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Resources/Bibles").path))
    }

    @Test func theCheckFailsWhenTheAppHoldsAnythingElse() throws {
        let root = try scratch()
        let app = root.appendingPathComponent("Test.app")
        let dir = app.appendingPathComponent("Contents/Resources/Bibles")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("invented".utf8).write(to: dir.appendingPathComponent("KJV.json"))
        #expect(try run("check_bundled_translations '\(app.path)'").status == 0)
        for stray in ["NKJV.json", ".hidden", "KJV.json.bak"] {
            try Data("invented".utf8).write(to: dir.appendingPathComponent(stray))
            let r = try run("check_bundled_translations '\(app.path)'")
            #expect(r.status == 1 && r.output.contains(stray), "\(stray): \(r.output)")
            try FileManager.default.removeItem(at: dir.appendingPathComponent(stray))
        }
    }
}
