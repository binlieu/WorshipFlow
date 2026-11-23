// SYS-015 (LIB-005, SLIDE, MEDIA, CUE): the program package carries the new stored fields. The object fields travel inside the slide's objects; a video object
// names a bin item, which travels with its file and is renamed on import like a slide's own background; a clip's marks and markers travel with the clip. A
// package written before these fields existed still imports, a library that uses none of them exports the same manifest as before, and a package built to
// hurt (a time that is not a time, markers without number, a video with no clip) is refused or bounded before anything is written.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct SYS015_ProgramTests {
    private func refusal(_ package: URL) -> String? {
        do { _ = try ProgramPackageContents.open(package); return nil } catch let error as ProgramPackageError { return error.errorDescription } catch { return "other: \(error)" }
    }

    private func editAssets(_ package: URL, _ change: (inout [String: Any]) -> Void) throws {
        try editManifest(package) { root in
            var assets = root["mediaAssets"] as? [[String: Any]] ?? []
            for i in assets.indices { change(&assets[i]) }
            root["mediaAssets"] = assets
        }
    }

    /// The Sermon's two slides get: a hidden, named, locked text box with fit and fill; and a video object on the Loop clip.
    private func decorate(_ home: HomeProgram) async throws -> (box: SlideObject, video: SlideObject) {
        var slides = try await home.store.slides(of: home.songTwo)
        var text = TextObject(text: "Caption", style: Theme.fullScreen.primary.style)
        text.fit = .shrinkToFit
        text.backgroundFill = ColorRGBA(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.5)
        let box = SlideObject(frame: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.2), name: "Caption box", isHidden: true, isLocked: true, content: .text(text))
        let video = SlideObject(frame: NormalizedRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4), name: "Loop", content: .video(VideoObject(mediaID: home.assetID, loops: false, muted: true)))
        slides[0].content.objects = [box, video]
        try await home.store.updateSlide(slides[0])
        return (box, video)
    }

    // MARK: Slide objects

    @Test func theObjectFieldsAndAVideoObjectTravelAndTheClipGoesWithIt() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let (box, video) = try await decorate(home)
        let package = try await home.export()
        let manifest = try String(contentsOf: package.appendingPathComponent("program.json"), encoding: .utf8)
        #expect(!manifest.contains(rig.root.path) && !manifest.contains("ExternalDrive"))
        let contents = try ProgramPackageContents.open(package)
        let entry = try #require(contents.document.presentations.first { $0.id == home.songTwo }?.slides.first)
        #expect(entry.objects == [box, video])
        #expect(contents.document.mediaAssets.contains { $0.id == home.assetID })

        try FileManager.default.removeItem(at: rig.url("ExternalDrive"))
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        let slide = try #require(try await church.slides(of: home.songTwo).first)
        #expect(slide.content.objects == [box, video])
        let asset = try #require(try await church.mediaAssets(kind: nil).first { $0.id == home.assetID })
        #expect(try Data(contentsOf: URL(fileURLWithPath: asset.path)) == rig.bytes(seed: 4, count: 5_000))
    }

    @Test func aVideoObjectIsPointedAtTheExistingBinEntryWhenTheLibraryAlreadyHasTheFile() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let (_, video) = try await decorate(home)
        let contents = try ProgramPackageContents.open(try await home.export())
        let church = try rig.openStore("church")
        let entry = try #require(contents.document.mediaAssets.first { $0.id == home.assetID })
        let media = try #require(contents.document.media.first { $0.file == entry.file })
        let folder = "Media/Imported/\(contents.document.programID.uuidString)"
        let local = rig.url("church", folder, "\(try #require(media.sha256)).mov").path
        let existing = try await church.addMediaAsset(name: "Loop (mine)", kind: .video, path: local, bookmark: nil, duration: 3, pixelWidth: 640, pixelHeight: 360)
        #expect(existing.id != home.assetID)
        _ = try await ProgramImporter.apply(contents, into: church)
        let objects = try #require(try await church.slides(of: home.songTwo).first).content.objects
        guard case .video(let v) = objects[1].content else { Issue.record("video lost"); return }
        #expect(v.mediaID == existing.id && v.loops == false && v.muted)
        #expect(objects[1].name == video.name)
        #expect(try await church.mediaAssets(kind: nil).contains { $0.id == v.mediaID })
    }

    @Test func aVideoObjectWhoseClipIsNoLongerInTheLibraryIsLeftOutWithAWarning() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let (box, _) = try await decorate(home)
        let gone = SlideObject(frame: .full, content: .video(VideoObject(mediaID: UUID())))
        var slides = try await home.store.slides(of: home.songTwo)
        slides[0].content.objects.append(gone)
        try await home.store.updateSlide(slides[0])
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID, appVersion: "9.9.9")
        let exported = try #require(plan.document.presentations.first { $0.id == home.songTwo }?.slides.first)
        #expect(exported.objects.map(\.id).contains(gone.id) == false && exported.objects.first == box)
        #expect(plan.warnings.contains { $0.contains("video") })
    }

    @Test func aLibraryThatUsesNoNewFieldWritesNoNewKey() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let text = try String(contentsOf: try await home.export().appendingPathComponent("program.json"), encoding: .utf8)
        for key in ["isHidden", "isLocked", "\"name\" : \"Caption", "markIn", "markOut", "markers", "\"fit\" :", "backgroundFill", "\"video\" : {"] {
            #expect(!text.contains(key), "\(key)")
        }
    }

    @Test func aPackageWrittenBeforeV15StillImports() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await decorate(home)
        let package = try await home.export()
        // Remove everything v15 added: a v14 writer knew none of it (and had no video object).
        try editSlides(package) { slide in
            guard var objects = slide["objects"] as? [[String: Any]] else { return }
            objects = objects.filter { ($0["content"] as? [String: Any])?["video"] == nil }
            for i in objects.indices { for key in ["name", "isHidden", "isLocked"] { objects[i].removeValue(forKey: key) } }
            slide["objects"] = objects
        }
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        let objects = try #require(try await church.slides(of: home.songTwo).first).content.objects
        #expect(objects.count == 1 && objects[0].name == nil && !objects[0].isHidden && !objects[0].isLocked)
    }

    @Test func twoPresentationsThatDifferOnlyInAFlagAreNotTheSame() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await decorate(home)
        let contents = try ProgramPackageContents.open(try await home.export())
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        #expect(try await ProgramImporter.summarize(contents, into: church).isNothingToImport)
        let slide = try #require(try await church.slides(of: home.songTwo).first)
        _ = try await church.setSlideObjectHidden(false, objectID: slide.content.objects[0].id, inSlide: slide.id)
        #expect(try await ProgramImporter.summarize(contents, into: church).conflicting == ["Invented Sermon"])
    }

    @Test func aHostileObjectNameIsBoundedOnImport() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await decorate(home)
        let package = try await home.export()
        let huge = String(repeating: "N", count: 2_000_000)
        try editSlides(package) { slide in
            guard var objects = slide["objects"] as? [[String: Any]], !objects.isEmpty else { return }
            objects[0]["name"] = huge
            slide["objects"] = objects
        }
        let contents = try ProgramPackageContents.open(package)
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        let name = try #require(try await church.slides(of: home.songTwo).first?.content.objects.first?.name)
        #expect(name.count == SlideObject.maxNameLength)
    }

    @Test func aVideoObjectWithNoClipInThePackageIsRefused() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await decorate(home)
        let package = try await home.export()
        try editSlides(package) { slide in
            guard var objects = slide["objects"] as? [[String: Any]] else { return }
            for i in objects.indices {
                if var content = objects[i]["content"] as? [String: Any], var video = content["video"] as? [String: Any], var inner = video["_0"] as? [String: Any] {
                    inner["mediaID"] = UUID().uuidString
                    video["_0"] = inner
                    content["video"] = video
                    objects[i]["content"] = content
                }
            }
            slide["objects"] = objects
        }
        let text = try #require(refusal(package))
        #expect(text.contains("Nothing was imported") && text.contains("video"))
    }

    // MARK: Marks and markers

    private func giveTheLoopMarks(_ home: HomeProgram) async throws -> [MediaMarker] {
        _ = try await home.store.setMediaMarks(markIn: 0.5, markOut: 2.5, forAsset: home.assetID)
        let a = try await home.store.addMediaMarker(forAsset: home.assetID, time: 2, name: "Tag",
                                                    actions: #"{"version":1,"actions":[{"kind":"media.stopForeground"}]}"#)
        let b = try await home.store.addMediaMarker(forAsset: home.assetID, time: 1, name: "Chorus in")
        return [b, a]       // time order
    }

    @Test func aClipsMarksAndMarkersTravelAndComeBack() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let expected = try await giveTheLoopMarks(home)
        let contents = try ProgramPackageContents.open(try await home.export())
        let entry = try #require(contents.document.mediaAssets.first { $0.id == home.assetID })
        #expect(entry.markIn == 0.5 && entry.markOut == 2.5 && entry.markers.map(\.time) == [1, 2] && entry.markers.map(\.name) == ["Chorus in", "Tag"])
        try FileManager.default.removeItem(at: rig.url("ExternalDrive"))
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(contents, into: church)
        let asset = try #require(try await church.mediaAssets(kind: nil).first { $0.id == home.assetID })
        #expect(asset.markIn == 0.5 && asset.markOut == 2.5)
        let markers = try await church.mediaMarkers(forAsset: asset.id)
        #expect(markers.map(\.time) == expected.map(\.time) && markers.map(\.name) == expected.map(\.name) && markers.map(\.actions) == expected.map(\.actions))
    }

    @Test func aMarkerActionThatPlaysAnotherClipBringsThatClipAlong() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let stinger = try await home.store.addMediaAsset(name: "Stinger", kind: .video, path: rig.url("ExternalDrive", "pictures", "stinger.mov").path,
                                                         bookmark: nil, duration: 2, pixelWidth: 64, pixelHeight: 36)
        try rig.write(rig.bytes(seed: 21, count: 1_000), to: URL(fileURLWithPath: stinger.path))
        _ = try await home.store.addMediaMarker(forAsset: home.assetID, time: 1, actions: #"{"version":1,"actions":[{"kind":"media.playForeground","assetID":"\#(stinger.id.uuidString.lowercased())"}]}"#)
        let contents = try ProgramPackageContents.open(try await home.export())
        #expect(contents.document.mediaAssets.contains { $0.id == stinger.id })
    }

    @Test func aMarkerActionIsPointedAtTheExistingBinEntryWhenTheLibraryAlreadyHasThatClip() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let stinger = try await home.store.addMediaAsset(name: "Stinger", kind: .video, path: rig.url("ExternalDrive", "pictures", "stinger.mov").path,
                                                         bookmark: nil, duration: 2, pixelWidth: 64, pixelHeight: 36)
        try rig.write(rig.bytes(seed: 21, count: 1_000), to: URL(fileURLWithPath: stinger.path))
        _ = try await home.store.addMediaMarker(forAsset: home.assetID, time: 1, actions: #"{"version":1,"actions":[{"kind":"media.playForeground","assetID":"\#(stinger.id.uuidString.lowercased())"}]}"#)
        let contents = try ProgramPackageContents.open(try await home.export())
        let entry = try #require(contents.document.mediaAssets.first { $0.id == stinger.id })
        let media = try #require(contents.document.media.first { $0.file == entry.file })
        let folder = "Media/Imported/\(contents.document.programID.uuidString)"
        let church = try rig.openStore("church")
        let mine = try await church.addMediaAsset(name: "Stinger (mine)", kind: .video, path: rig.url("church", folder, "\(try #require(media.sha256)).mov").path,
                                                  bookmark: nil, duration: 2, pixelWidth: 64, pixelHeight: 36)
        _ = try await ProgramImporter.apply(contents, into: church)
        let markers = try await church.mediaMarkers(forAsset: home.assetID)
        #expect(markers.count == 1 && markers[0].actions.contains(mine.id.uuidString.lowercased()) && !markers[0].actions.contains(stinger.id.uuidString.lowercased()))
    }

    @Test func aPackageWrittenBeforeV15HasNoMarksAndImportsWithNone() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await giveTheLoopMarks(home)
        let package = try await home.export()
        try editAssets(package) { for key in ["markIn", "markOut", "markers"] { $0.removeValue(forKey: key) } }
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        let asset = try #require(try await church.mediaAssets(kind: nil).first { $0.id == home.assetID })
        #expect(asset.markIn == nil && asset.markOut == nil)
        #expect(try await church.mediaMarkers(forAsset: asset.id).isEmpty)
    }

    @Test func marksAndMarkersThatAreNotRealAreRefused() async throws {
        let bad: [(String, Any)] = [("markIn", -1.0), ("markIn", 1e300), ("markOut", 99.0), ("markOut", -0.5)]
        for (key, value) in bad {
            let rig = try Rig()
            let home = try await HomeProgram.make(rig)
            _ = try await giveTheLoopMarks(home)
            let package = try await home.export()
            try editAssets(package) { $0[key] = value }
            let text = try #require(refusal(package), "\(key) \(value) should be refused")
            #expect(text.contains("Nothing was imported"), "\(text)")
        }
        // In after out.
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        _ = try await giveTheLoopMarks(home)
        let package = try await home.export()
        try editAssets(package) { $0["markIn"] = 2.9; $0["markOut"] = 1.0 }
        #expect(refusal(package) != nil)
    }

    @Test func aMarkerWithABadTimeOrActionsOrTooManyMarkersIsRefused() async throws {
        func marker(_ time: Any, actions: Any = ["version": 1, "actions": [Any]()] as [String: Any]) -> [String: Any] {
            ["id": UUID().uuidString, "time": time, "actions": actions]
        }
        let cases: [[[String: Any]]] = [
            [marker(-1.0)], [marker(1e300)], [marker(99.0)],
            [marker(1.0, actions: "not an object")], [marker(1.0, actions: ["version": 1])], [marker(1.0, actions: ["version": 0, "actions": [Any]()])],
            [marker(1.0, actions: ["version": 1, "actions": [["kind": String(repeating: "x", count: 100_000)]]])],
            (0..<(MediaMarker.maxPerAsset + 1)).map { _ in marker(1.0) },
        ]
        for markers in cases {
            let rig = try Rig()
            let home = try await HomeProgram.make(rig)
            let package = try await home.export()
            try editAssets(package) { $0["markers"] = markers }
            #expect(refusal(package) != nil, "\(markers.count) marker(s): \(markers.first.map { String(describing: $0).prefix(60) } ?? "")")
        }
    }

    @Test func aHostileMarkerNameIsBounded() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        try editAssets(package) { $0["markers"] = [["id": UUID().uuidString, "time": 1.0, "name": String(repeating: "M", count: 1_000_000), "actions": ["version": 1, "actions": [Any]()] as [String: Any]]] }
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(package), into: church)
        let markers = try await church.mediaMarkers(forAsset: home.assetID)
        #expect(markers.count == 1 && markers[0].name?.count == MediaMarker.maxNameLength)
    }
}
