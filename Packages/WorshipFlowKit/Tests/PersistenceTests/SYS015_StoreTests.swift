// SYS-015 (SLIDE, MEDIA, CUE, OUT): the store methods the feature slices call for the fields migration v15 added. Each stores, reloads, refuses a value
// that is not real, and leaves everything else alone.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct SYS015_StoreTests {
    private let frame = NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)

    private func slideWithObjects() async throws -> (LibraryStore, Presentation, Slide, [SlideObject]) {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        let text = SlideObject(frame: frame, content: .text(TextObject(text: "Caption", style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white),
                                                                      fit: .shrinkToFit, backgroundFill: ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0.5))))
        let shape = SlideObject(frame: frame, content: .shape(ShapeObject(shape: .ellipse, fill: .white)))
        let video = SlideObject(frame: frame, content: .video(VideoObject(mediaID: UUID(), loops: false, muted: true)))
        let slide = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one", objects: [text, shape, video]))
        return (store, p, slide, [text, shape, video])
    }

    // MARK: Slide objects

    @Test func everyNewObjectFieldIsStoredAndReloaded() async throws {
        let (store, p, slide, objects) = try await slideWithObjects()
        #expect(slide.content.objects == objects)
        var edited = slide
        edited.content.objects[0].name = "Caption box"
        edited.content.objects[0].isHidden = true
        edited.content.objects[1].isLocked = true
        try await store.updateSlide(edited)
        let back = try #require(try await store.slides(of: p.id).first)
        #expect(back.content.objects == edited.content.objects)
        #expect(back.content.objects.map(\.name) == ["Caption box", nil, nil])
        #expect(back.content.objects.map(\.isHidden) == [true, false, false] && back.content.objects.map(\.isLocked) == [false, true, false])
        guard case .video(let v) = back.content.objects[2].content else { Issue.record("video lost"); return }
        #expect(v == VideoObject(mediaID: v.mediaID, loops: false, muted: true))
    }

    @Test func theSetMethodsChangeOneFlagOfOneObjectAndNothingElse() async throws {
        let (store, p, slide, objects) = try await slideWithObjects()
        let before = try await store.slides(of: p.id)
        let named = try await store.setSlideObjectName("  Lyrics frame ", objectID: objects[1].id, inSlide: slide.id)
        #expect(named.content.objects[1].name == "Lyrics frame")
        _ = try await store.setSlideObjectHidden(true, objectID: objects[2].id, inSlide: slide.id)
        let locked = try await store.setSlideObjectLocked(true, objectID: objects[0].id, inSlide: slide.id)
        #expect(locked.content.objects.map(\.isLocked) == [true, false, false])
        var expected = before[0]
        expected.content.objects[1].name = "Lyrics frame"
        expected.content.objects[2].isHidden = true
        expected.content.objects[0].isLocked = true
        let after = try await store.slides(of: p.id)
        #expect(after.count == 1 && after[0].content == expected.content && after[0].notes == before[0].notes)
        // Clearing.
        _ = try await store.setSlideObjectName(nil, objectID: objects[1].id, inSlide: slide.id)
        _ = try await store.setSlideObjectHidden(false, objectID: objects[2].id, inSlide: slide.id)
        let cleared = try #require(try await store.slides(of: p.id).first)
        #expect(cleared.content.objects.map(\.name) == [nil, nil, nil] && cleared.content.objects.map(\.isHidden) == [false, false, false])
    }

    @Test func theSetMethodsRefuseAnUnknownSlideOrObject() async throws {
        let (store, _, slide, objects) = try await slideWithObjects()
        await #expect(throws: StoreError.notFound) { _ = try await store.setSlideObjectHidden(true, objectID: UUID(), inSlide: slide.id) }
        await #expect(throws: StoreError.notFound) { _ = try await store.setSlideObjectLocked(true, objectID: objects[0].id, inSlide: UUID()) }
        await #expect(throws: StoreError.notFound) { _ = try await store.setSlideObjectName("x", objectID: UUID(), inSlide: slide.id) }
    }

    @Test func aSlideWithNoNewValueStoresTheSameJSONAsBeforeV15() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        let id = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!
        let object = SlideObject(id: id, frame: NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25), opacity: 1,
                                 content: .shape(ShapeObject(shape: .ellipse, fill: .white)))
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one", objects: [object]))
        let stored = try await store.writer.read { try String.fetchOne($0, sql: "SELECT objects FROM slide") }
        let expected = #"[{"content":{"shape":{"_0":{"fill":{"alpha":1,"blue":1,"green":1,"red":1},"shape":{"ellipse":{}},"strokeWidth":0}}},"frame":{"height":0.25,"width":0.5,"x":0.25,"y":0.5},"id":"00000000-0000-0000-0000-0000000000AA","opacity":1}]"#
        #expect(stored == expected)
    }

    @Test func aReflowCarriesTheNewFieldsWithTheObjectsOfTheSlideThatTakesOver() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        func reflowed(_ text: String) -> [ReflowResult] { Reflow.contents(primary: text, secondary: nil, maxLines: 1) }
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\nb"))
        var slide = try #require(try await store.slides(of: p.id).first { $0.content.primary == "b" })
        slide.content.objects = [SlideObject(frame: frame, name: "Mark", isHidden: true, isLocked: true,
                                             content: .video(VideoObject(mediaID: UUID())))]
        try await store.updateSlide(slide)
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\nnew first\nb"))
        let carried = try #require(try await store.slides(of: p.id).first { $0.content.primary == "b" })
        #expect(carried.content.objects == slide.content.objects)
    }

    // MARK: Media marks

    private func clip(_ store: LibraryStore, duration: Double? = 60, kind: MediaKind = .video, path: String = "/m/c.mov") async throws -> MediaAsset {
        try await store.addMediaAsset(name: "Clip", kind: kind, path: path, bookmark: nil, duration: duration, pixelWidth: nil, pixelHeight: nil)
    }

    @Test func markInAndMarkOutAreSetClearedAndReadBack() async throws {
        let store = try LibraryStore.inMemory()
        let asset = try await clip(store)
        #expect(asset.markIn == nil && asset.markOut == nil)
        let both = try await store.setMediaMarks(markIn: 5, markOut: 50, forAsset: asset.id)
        #expect(both.markIn == 5 && both.markOut == 50)
        #expect(try await store.mediaAssets(kind: nil).first?.markOut == 50)
        let onlyIn = try await store.setMediaMarks(markIn: 7.5, markOut: nil, forAsset: asset.id)       // nil clears that one
        #expect(onlyIn.markIn == 7.5 && onlyIn.markOut == nil)
        let equal = try await store.setMediaMarks(markIn: 9, markOut: 9, forAsset: asset.id)
        #expect(equal.markIn == 9 && equal.markOut == 9)
        let whole = try await store.setMediaMarks(markIn: 0, markOut: 60, forAsset: asset.id)
        #expect(whole.markOut == 60)
        let cleared = try await store.clearMediaMarks(forAsset: asset.id)
        #expect(cleared.markIn == nil && cleared.markOut == nil)
        let columns = try await store.writer.read { try Row.fetchOne($0, sql: "SELECT markIn, markOut FROM mediaAsset") }
        #expect(columns?["markIn"] as Double? == nil && columns?["markOut"] as Double? == nil)       // cleared means NULL
    }

    @Test func aMarkThatIsNotRealOrNotInsideTheClipIsRefusedAndNothingChanges() async throws {
        let store = try LibraryStore.inMemory()
        let asset = try await clip(store)
        _ = try await store.setMediaMarks(markIn: 5, markOut: 50, forAsset: asset.id)
        let bad: [(Double?, Double?)] = [(40, 30), (-1, nil), (nil, 61), (.nan, nil), (nil, .infinity), (1e300, nil), (nil, -0.001)]
        for (a, b) in bad {
            await #expect(throws: StoreError.invalidValue, "\(String(describing: a)) \(String(describing: b))") { _ = try await store.setMediaMarks(markIn: a, markOut: b, forAsset: asset.id) }
        }
        let unchanged = try #require(try await store.mediaAssets(kind: nil).first)
        #expect(unchanged.markIn == 5 && unchanged.markOut == 50)
        await #expect(throws: StoreError.notFound) { _ = try await store.setMediaMarks(markIn: 1, markOut: 2, forAsset: UUID()) }
        await #expect(throws: StoreError.notFound) { _ = try await store.clearMediaMarks(forAsset: UUID()) }
    }

    @Test func aPictureHasNoMarksAndAnUnknownLengthStillBoundsThem() async throws {
        let store = try LibraryStore.inMemory()
        let picture = try await clip(store, duration: nil, kind: .image, path: "/m/p.png")
        await #expect(throws: StoreError.invalidValue) { _ = try await store.setMediaMarks(markIn: 1, markOut: nil, forAsset: picture.id) }
        let unknown = try await clip(store, duration: nil, kind: .audio, path: "/m/s.wav")
        #expect(try await store.setMediaMarks(markIn: 1, markOut: 90, forAsset: unknown.id).markOut == 90)
        await #expect(throws: StoreError.invalidValue) { _ = try await store.setMediaMarks(markIn: 1, markOut: MediaClock.longest + 1, forAsset: unknown.id) }
    }

    // MARK: Markers

    @Test func markersAreAddedMovedRenamedAndDeletedAndListedInTimeOrder() async throws {
        let store = try LibraryStore.inMemory()
        let asset = try await clip(store)
        let other = try await clip(store, path: "/m/other.mov")
        let b = try await store.addMediaMarker(forAsset: asset.id, time: 30, name: "  Bridge ")
        let a = try await store.addMediaMarker(forAsset: asset.id, time: 10)
        let c = try await store.addMediaMarker(forAsset: asset.id, time: 30, name: "Tag", actions: #"{"version":1,"actions":[{"kind":"media.stopForeground"}]}"#)
        _ = try await store.addMediaMarker(forAsset: other.id, time: 1)
        #expect(b.name == "Bridge" && a.name == nil && a.actions == MediaMarker.emptyActions)
        #expect(c.actions == #"{"actions":[{"kind":"media.stopForeground"}],"version":1}"#)
        #expect(try await store.mediaMarkers(forAsset: asset.id).map(\.id) == [a.id, b.id, c.id])      // by time, then the order added
        #expect(try await store.mediaMarkers(forAsset: other.id).count == 1)

        let moved = try await store.moveMediaMarker(id: c.id, to: 5)
        #expect(moved.time == 5 && moved.id == c.id && moved.name == "Tag")
        #expect(try await store.mediaMarkers(forAsset: asset.id).map(\.id) == [c.id, a.id, b.id])
        let renamed = try await store.renameMediaMarker(id: a.id, to: "Verse 2")
        #expect(renamed.name == "Verse 2")
        #expect(try await store.renameMediaMarker(id: a.id, to: "   ").name == nil)
        let actions = try await store.setMediaMarkerActions(id: a.id, actions: #"{"version":1,"actions":[{"kind":"look.select","id":"X"}]}"#)
        #expect(actions.actions.contains("look.select"))
        try await store.deleteMediaMarker(id: b.id)
        #expect(try await store.mediaMarkers(forAsset: asset.id).map(\.id) == [c.id, a.id])
        await #expect(throws: StoreError.notFound) { try await store.deleteMediaMarker(id: b.id) }
        await #expect(throws: StoreError.notFound) { _ = try await store.moveMediaMarker(id: b.id, to: 1) }
        await #expect(throws: StoreError.notFound) { _ = try await store.mediaMarkers(forAsset: UUID()) }
    }

    @Test func aMarkerTimeOrActionsThatAreNotRealAreRefused() async throws {
        let store = try LibraryStore.inMemory()
        let asset = try await clip(store)
        for time in [-1.0, 60.5, .nan, .infinity, 1e300] {
            await #expect(throws: StoreError.invalidValue, "\(time)") { _ = try await store.addMediaMarker(forAsset: asset.id, time: time) }
        }
        for actions in ["", "[]", "{}", "{bad", #"{"version":1,"actions":5}"#] {
            await #expect(throws: StoreError.invalidValue) { _ = try await store.addMediaMarker(forAsset: asset.id, time: 1, actions: actions) }
        }
        let m = try await store.addMediaMarker(forAsset: asset.id, time: 1)
        await #expect(throws: StoreError.invalidValue) { _ = try await store.moveMediaMarker(id: m.id, to: 61) }
        await #expect(throws: StoreError.invalidValue) { _ = try await store.setMediaMarkerActions(id: m.id, actions: "nope") }
        #expect(try await store.mediaMarkers(forAsset: asset.id).map(\.time) == [1])
        await #expect(throws: StoreError.notFound) { _ = try await store.addMediaMarker(forAsset: UUID(), time: 1) }
    }

    @Test func aClipKeepsAtMostThePermittedNumberOfMarkers() async throws {
        let store = try LibraryStore.inMemory()
        let asset = try await clip(store)
        try await store.writer.write { db in
            for n in 0..<MediaMarker.maxPerAsset {
                try db.execute(sql: "INSERT INTO mediaMarker (id, assetID, time, name, actions, sortOrder, createdAt, updatedAt) VALUES (?, ?, 1, NULL, ?, ?, ?, ?)",
                               arguments: [UUID().uuidString, asset.id.uuidString, MediaMarker.emptyActions, n, Date(), Date()])
            }
        }
        await #expect(throws: StoreError.invalidValue) { _ = try await store.addMediaMarker(forAsset: asset.id, time: 2) }
    }

    @Test func removingTheAssetRemovesItsMarkersThroughTheStoreToo() async throws {
        let store = try LibraryStore.inMemory()
        let asset = try await clip(store)
        let m = try await store.addMediaMarker(forAsset: asset.id, time: 3)
        try await store.removeMediaAsset(id: asset.id)
        await #expect(throws: StoreError.notFound) { _ = try await store.moveMediaMarker(id: m.id, to: 4) }
    }

    // MARK: Screens

    @Test func screenProfilesWithNoNewValueStoreExactlyWhatTheyStoredBefore() async throws {
        let store = try LibraryStore.inMemory()
        let window = ScreenProfile(name: "Audience", role: .audience, destination: .window)
        let sdi = ScreenProfile(name: "Broadcast", role: .broadcast, destination: .sdi(deviceID: "d", connector: 1, keying: true, fillAlphaMode: .premultiplied),
                                connectedTo: ["ATEM 5"])
        try await store.saveScreenProfiles([window, sdi])
        let extras = try await store.writer.read { try String?.fetchAll($0, sql: "SELECT extra FROM screenProfile ORDER BY sortOrder") }
        #expect(extras.first! == nil)
        #expect(!(extras[1] ?? "").contains("signalChains"))
        #expect(!(extras[1] ?? "").contains("connectedToKey") && !(extras[1] ?? "").contains("screenLookID"))
        #expect(try await store.screenProfiles() == [window, sdi])
    }

    @Test func theKeyNoteTheChainAndTheLookOfAScreenAreStoredAndReloaded() async throws {
        let store = try LibraryStore.inMemory()
        let sdi = ScreenProfile(name: "Broadcast", role: .broadcast, destination: .sdi(deviceID: "d", connector: 1, keying: true, fillAlphaMode: .premultiplied),
                                mirrors: [.sdi(deviceID: "d", connector: 3, keying: true, fillAlphaMode: .premultiplied)])
        let other = ScreenProfile(name: "Audience", role: .audience, destination: .window)
        try await store.saveScreenProfiles([other, sdi])
        let look = Look(id: UUID(), name: "Morning")
        try await store.saveLook(look)

        try await store.setScreenKeyNote("ATEM key 1", mirror: nil, forScreen: sdi.id)
        try await store.setScreenKeyNote("Recorder key", mirror: 0, forScreen: sdi.id)
        let chain = [ChainNode(kind: .enclosure, label: "Thunderbolt box"), ChainNode(kind: .converter, label: "SDI to HDMI")]
        try await store.setScreenSignalChain(chain, mirror: nil, forScreen: sdi.id)
        try await store.setScreenLook(look.id, forScreen: sdi.id)

        let back = try await store.screenProfiles()
        #expect(back.map(\.name) == ["Audience", "Broadcast"] && back[0] == other)           // the other screen and the order are untouched
        let s = back[1]
        #expect(s.connectedKeyNote(mirror: nil) == "ATEM key 1" && s.connectedKeyNote(mirror: 0) == "Recorder key")
        #expect(s.signalChain(mirror: nil) == chain && s.signalChain(mirror: 0).isEmpty && s.screenLookID == look.id)
        #expect(s.destination == sdi.destination && s.mirrors == sdi.mirrors)

        try await store.setScreenKeyNote("", mirror: 0, forScreen: sdi.id)
        try await store.setScreenSignalChain([], mirror: nil, forScreen: sdi.id)
        try await store.setScreenLook(nil, forScreen: sdi.id)
        let cleared = try await store.screenProfiles()[1]
        #expect(cleared.connectedToKey == ["ATEM key 1"] && cleared.signalChains.isEmpty && cleared.screenLookID == nil)
    }

    @Test func aWindowScreenCanCarryTheNewValuesToo() async throws {
        let store = try LibraryStore.inMemory()
        let window = ScreenProfile(name: "Stage", role: .stage, destination: .window)
        try await store.saveScreenProfiles([window])
        try await store.setScreenSignalChain([ChainNode(kind: .other, label: "Splitter")], mirror: nil, forScreen: window.id)
        let back = try await store.screenProfiles()[0]
        #expect(back.signalChain(mirror: nil) == [ChainNode(kind: .other, label: "Splitter")] && back.destination == .window)
    }

    @Test func aScreenLookMustExistAndDeletingTheLookClearsItFromTheScreens() async throws {
        let store = try LibraryStore.inMemory()
        let a = ScreenProfile(name: "A", role: .audience, destination: .window)
        let b = ScreenProfile(name: "B", role: .stage, destination: .window)
        try await store.saveScreenProfiles([a, b])
        await #expect(throws: StoreError.invalidReference) { try await store.setScreenLook(UUID(), forScreen: a.id) }
        await #expect(throws: StoreError.notFound) { try await store.setScreenLook(nil, forScreen: UUID()) }
        await #expect(throws: StoreError.notFound) { try await store.setScreenKeyNote("x", mirror: nil, forScreen: UUID()) }
        await #expect(throws: StoreError.notFound) { try await store.setScreenSignalChain([], mirror: nil, forScreen: UUID()) }
        let look = Look(id: UUID(), name: "L")
        let keep = Look(id: UUID(), name: "K")
        try await store.saveLook(look)
        try await store.saveLook(keep)
        try await store.setScreenLook(look.id, forScreen: a.id)
        try await store.setScreenLook(keep.id, forScreen: b.id)
        try await store.deleteLook(id: look.id)
        let after = try await store.screenProfiles()
        #expect(after[0].screenLookID == nil && after[1].screenLookID == keep.id)
        #expect(after[0].name == "A" && after[1].name == "B")
    }

    @Test func savingTheWholeSetKeepsTheNewValues() async throws {
        let store = try LibraryStore.inMemory()
        var p = ScreenProfile(name: "Broadcast", role: .broadcast, destination: .sdi(deviceID: "d", connector: 1, keying: true, fillAlphaMode: .straight))
        p.setConnectedKeyNote("Key in", mirror: nil)
        p.setSignalChain([ChainNode(kind: .converter, label: "Conv")], mirror: nil)
        let look = Look(id: UUID(), name: "L")
        try await store.saveLook(look)
        p.screenLookID = look.id
        try await store.saveScreenProfiles([p])
        #expect(try await store.screenProfiles() == [p])
    }
}
