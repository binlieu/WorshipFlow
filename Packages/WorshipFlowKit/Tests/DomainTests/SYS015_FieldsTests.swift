// SYS-015 (SLIDE, MEDIA, STAGE, OUT, CUE): the new stored fields as Domain values. Old stored JSON decodes to the documented defaults, a value
// at its default writes no key (so what an old library stores is byte-for-byte what it stored), each new field round-trips, a hostile value is
// bounded, the compositor skips a hidden object and draws nothing for a video object (that is the feature slice's work), and the section name a stage
// element needs travels with the deck.
import Testing
import Foundation
import Domain

@Suite struct SYS015_FieldsTests {
    private let frame = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    private func text(_ words: String = "Words") -> TextObject { TextObject(text: words, style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white)) }

    // MARK: Slide objects

    @Test func anObjectStoredBeforeV15DecodesToTheDefaults() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","frame":{"x":0.1,"y":0.2,"width":0.3,"height":0.4},"opacity":0.5,"content":{"text":{"_0":{"text":"Old","style":{"fontName":"Helvetica Neue","fontSize":40,"color":{"red":1,"green":1,"blue":1,"alpha":1},"outlineWidth":0,"outlineColor":{"red":0,"green":0,"blue":0,"alpha":1}},"alignment":"center","verticalAlignment":"center"}}}}"#
        let object = try JSONDecoder().decode(SlideObject.self, from: Data(json.utf8))
        #expect(object.name == nil && object.isHidden == false && object.isLocked == false)
        guard case .text(let t) = object.content else { Issue.record("not text"); return }
        #expect(t.fit == .none && t.backgroundFill == nil && t.text == "Old")
    }

    @Test func anObjectAtItsDefaultsWritesNoNewKey() throws {
        for content: SlideObject.Content in [.text(text()), .shape(ShapeObject(shape: .ellipse, fill: .white)), .image(ImageObject(path: "/p.png"))] {
            let json = try encode(SlideObject(frame: frame, content: content))
            for key in ["name", "isHidden", "isLocked", "fit", "backgroundFill"] { #expect(!json.contains("\"\(key)\":"), "\(key) in \(json)") }
        }
    }

    @Test func eachNewObjectFieldRoundTrips() throws {
        let fill = ColorRGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.5)
        var t = text()
        t.fit = .shrinkToFit
        t.backgroundFill = fill
        let object = SlideObject(frame: frame, opacity: 0.7, name: "Title", isHidden: true, isLocked: true, content: .text(t))
        let back = try JSONDecoder().decode(SlideObject.self, from: Data(try encode(object).utf8))
        #expect(back == object)
        #expect(back.name == "Title" && back.isHidden && back.isLocked)
        guard case .text(let bt) = back.content else { Issue.record("not text"); return }
        #expect(bt.fit == .shrinkToFit && bt.backgroundFill == fill)
        #expect(try encode(TextFit.shrinkToFit) == "\"shrinkToFit\"" && TextFit.allCases == [.none, .shrinkToFit])
    }

    @Test func aNameIsTrimmedBoundedAndEmptyIsNone() throws {
        #expect(SlideObject(frame: frame, name: "  Title  ", content: .text(text())).name == "Title")
        #expect(SlideObject(frame: frame, name: "   ", content: .text(text())).name == nil)
        let long = String(repeating: "x", count: 5_000)
        let made = SlideObject(frame: frame, name: long, content: .text(text()))
        #expect(made.name?.count == SlideObject.maxNameLength)
        var assigned = made
        assigned.name = "\n"
        #expect(assigned.name == nil)
        let json = #"{"id":"\#(UUID().uuidString)","frame":{"x":0,"y":0,"width":1,"height":1},"name":"\#(long)","content":{"image":{"_0":{"path":"/p.png","contentMode":"fit"}}}}"#
        #expect(try JSONDecoder().decode(SlideObject.self, from: Data(json.utf8)).name?.count == SlideObject.maxNameLength)
    }

    @Test func aVideoObjectIsAContentCaseWithItsOwnDefaults() throws {
        let media = UUID()
        let object = SlideObject(frame: frame, content: .video(VideoObject(mediaID: media)))
        let back = try JSONDecoder().decode(SlideObject.self, from: Data(try encode(object).utf8))
        #expect(back == object)
        guard case .video(let v) = back.content else { Issue.record("not video"); return }
        #expect(v.mediaID == media && v.loops == true && v.muted == true)
        let bare = #"{"mediaID":"\#(media.uuidString)"}"#
        let decoded = try JSONDecoder().decode(VideoObject.self, from: Data(bare.utf8))
        #expect(decoded == VideoObject(mediaID: media, loops: true, muted: true))
        let loud = VideoObject(mediaID: media, loops: false, muted: false)
        #expect(try JSONDecoder().decode(VideoObject.self, from: Data(try encode(loud).utf8)) == loud)
    }

    // MARK: Rendering: one rule added, one thing left to the feature slice

    private func live(_ content: SlideContent) -> ShowState {
        var s = ShowState(); s.apply(.load(ShowDeck(presentationID: UUID(), slides: [content]))); s.apply(.trigger(index: 0)); return s
    }
    private func box(_ n: Int, hidden: Bool = false) -> SlideObject {
        SlideObject(id: UUID(), frame: NormalizedRect(x: 0.1 * Double(n), y: 0, width: 0.1, height: 0.1), isHidden: hidden,
                    content: .shape(ShapeObject(shape: .rectangle, fill: .white)))
    }

    @Test func aHiddenObjectIsNotDrawnAndTheOthersKeepTheirOrder() {
        let objects = [box(1), box(2, hidden: true), box(3)]
        let scene = SceneComposer.scene(for: .audience, state: live(SlideContent(primary: "Grace", objects: objects)), theme: .fullScreen, look: .standard, props: [])
        #expect(scene.objectLayers == [objects[0].sceneLayer, objects[2].sceneLayer])
        let allHidden = SceneComposer.scene(for: .audience, state: live(SlideContent(primary: "Grace", objects: [box(1, hidden: true)])), theme: .fullScreen, look: .standard, props: [])
        #expect(allHidden.objectLayers.isEmpty)
    }

    @Test func aLockedObjectIsStillDrawn() {
        let locked = SlideObject(frame: frame, isLocked: true, content: .shape(ShapeObject(shape: .rectangle, fill: .white)))
        let scene = SceneComposer.scene(for: .audience, state: live(SlideContent(primary: "Grace", objects: [locked])), theme: .fullScreen, look: .standard, props: [])
        #expect(scene.objectLayers.count == 1)
    }

    @Test func aVideoObjectDrawsNothingYetAndDoesNotStopTheOthers() {
        let video = SlideObject(frame: frame, content: .video(VideoObject(mediaID: UUID())))
        let objects = [box(1), video, box(3)]
        let scene = SceneComposer.scene(for: .audience, state: live(SlideContent(primary: "Grace", objects: objects)), theme: .fullScreen, look: .standard, props: [])
        #expect(scene.objectLayers == [objects[0].sceneLayer, objects[2].sceneLayer])
        #expect(video.drawableLayer == nil && objects[0].drawableLayer != nil)
        #expect(box(1, hidden: true).drawableLayer == nil)
    }

    // MARK: Media marks and markers

    @Test func anAssetStoredBeforeV15HasNoMarks() {
        let asset = MediaAsset(name: "Clip", kind: .video, path: "/c.mov", duration: 10)
        #expect(asset.markIn == nil && asset.markOut == nil)
        #expect(MediaAsset(name: "Clip", kind: .video, path: "/c.mov", duration: 10, markIn: 2, markOut: 8).markOut == 8)
    }

    @Test func marksAreValidatedAgainstTheClipLength() {
        #expect(MediaMarks.isValid(markIn: nil, markOut: nil, length: 10))
        #expect(MediaMarks.isValid(markIn: 0, markOut: 10, length: 10))
        #expect(MediaMarks.isValid(markIn: 3, markOut: 3, length: 10))
        #expect(MediaMarks.isValid(markIn: 3, markOut: nil, length: nil))
        #expect(!MediaMarks.isValid(markIn: 5, markOut: 4, length: 10))
        #expect(!MediaMarks.isValid(markIn: -1, markOut: nil, length: 10))
        #expect(!MediaMarks.isValid(markIn: nil, markOut: 10.5, length: 10))
        #expect(!MediaMarks.isValid(markIn: .nan, markOut: nil, length: 10))
        #expect(!MediaMarks.isValid(markIn: nil, markOut: .infinity, length: nil))
        #expect(!MediaMarks.isValid(markIn: 1e300, markOut: nil, length: nil))
        #expect(MediaMarks.isValidTime(0, length: 10) && MediaMarks.isValidTime(10, length: 10))
        #expect(!MediaMarks.isValidTime(10.1, length: 10) && !MediaMarks.isValidTime(-0.1, length: 10) && !MediaMarks.isValidTime(.nan, length: nil))
    }

    @Test func markerActionsMustBeTheVersionedJSONTheCueRowsUse() throws {
        #expect(MediaMarker.emptyActions == #"{"actions":[],"version":1}"#)
        #expect(MediaMarker.validatedActions(MediaMarker.emptyActions) == MediaMarker.emptyActions)
        let one = #"{"version":1,"actions":[{"kind":"media.stopForeground"}]}"#
        #expect(MediaMarker.validatedActions(one) == #"{"actions":[{"kind":"media.stopForeground"}],"version":1}"#)
        for bad in ["", "null", "[]", #"{"version":1}"#, #"{"actions":[]}"#, #"{"version":"1","actions":[]}"#, #"{"version":1,"actions":{}}"#, "{not json",
                    #"{"version":0,"actions":[]}"#, #"{"version":1,"actions":[1]}"#,
                    #"{"version":1,"actions":["# + String(repeating: #"{"kind":"x"},"#, count: 10_000) + #"{"kind":"x"}]}"#] {
            #expect(MediaMarker.validatedActions(bad) == nil, "\(bad.prefix(40))")
        }
        #expect(MediaMarker.cleanName("  Chorus in  ") == "Chorus in" && MediaMarker.cleanName(" ") == nil && MediaMarker.cleanName(nil) == nil)
        #expect(MediaMarker.cleanName(String(repeating: "x", count: 999))?.count == MediaMarker.maxNameLength)
    }

    // MARK: Screens

    @Test func aScreenProfileStoredBeforeV15HasNoKeyNoteNoChainAndNoLook() throws {
        let profile = ScreenProfile(name: "Broadcast", role: .broadcast, destination: .window)
        #expect(profile.connectedToKey.isEmpty && profile.signalChains.isEmpty && profile.screenLookID == nil)
        #expect(profile.connectedKeyNote(mirror: nil) == nil && profile.signalChain(mirror: nil).isEmpty)
        let old = #"{"id":"\#(UUID().uuidString)","name":"A","role":"audience","destination":{"window":{}},"isEnabled":true}"#
        let decoded = try JSONDecoder().decode(ScreenProfile.self, from: Data(old.utf8))
        #expect(decoded.connectedToKey.isEmpty && decoded.signalChains.isEmpty && decoded.screenLookID == nil)
    }

    @Test func theKeyNoteAndTheChainAreKeptPerDestinationAndTrimmed() throws {
        var profile = ScreenProfile(name: "Broadcast", role: .broadcast,
                                    destination: .sdi(deviceID: "d", connector: 1, keying: true, fillAlphaMode: .premultiplied),
                                    mirrors: [.sdi(deviceID: "d", connector: 3, keying: true, fillAlphaMode: .premultiplied)])
        profile.setConnectedKeyNote("  ATEM key 1 ", mirror: nil)
        profile.setConnectedKeyNote("Recorder key", mirror: 0)
        profile.setConnectedKeyNote("lost", mirror: 4)                  // no such mirror
        #expect(profile.connectedKeyNote(mirror: nil) == "ATEM key 1" && profile.connectedKeyNote(mirror: 0) == "Recorder key")
        #expect(profile.connectedToKey == ["ATEM key 1", "Recorder key"])
        profile.setConnectedKeyNote("", mirror: 0)
        #expect(profile.connectedToKey == ["ATEM key 1"])
        let chain = [ChainNode(kind: .enclosure, label: " Thunderbolt box "), ChainNode(kind: .converter, label: "SDI to HDMI"), ChainNode(kind: .other, label: "")]
        profile.setSignalChain(chain, mirror: nil)
        #expect(profile.signalChain(mirror: nil) == [ChainNode(kind: .enclosure, label: "Thunderbolt box"), ChainNode(kind: .converter, label: "SDI to HDMI"), ChainNode(kind: .other, label: "")])
        profile.setSignalChain(Array(repeating: ChainNode(kind: .other, label: String(repeating: "y", count: 900)), count: 40), mirror: 0)
        #expect(profile.signalChain(mirror: 0).count == ScreenProfile.maxChainLength && profile.signalChain(mirror: 0).allSatisfy { $0.label.count == ChainNode.maxLabelLength })
        profile.setSignalChain([], mirror: 0)
        #expect(profile.signalChains.count == 1)
        let back = try JSONDecoder().decode(ScreenProfile.self, from: Data(try encode(profile).utf8))
        #expect(back == profile)
        var withLook = profile
        withLook.screenLookID = UUID()
        #expect(try JSONDecoder().decode(ScreenProfile.self, from: Data(try encode(withLook).utf8)).screenLookID == withLook.screenLookID)
    }

    // MARK: Section names for the stage (item 3: no stored field)

    @Test func theDeckCarriesTheSectionNameOfEverySlideAndTheShowStateReadsLiveAndNext() {
        let group = UUID(), other = UUID()
        let pid = UUID()
        func slide(_ n: Int, _ g: UUID?) -> Slide { Slide(id: UUID(), presentationID: pid, sortOrder: n, content: SlideContent(primary: "s\(n)"), groupID: g) }
        let slides = [slide(0, group), slide(1, group), slide(2, other), slide(3, nil)]
        let groups = [SlideGroup(id: group, presentationID: pid, name: "Verse 1"), SlideGroup(id: other, presentationID: pid, name: "Chorus")]
        let names = ArrangementResolver.sectionNames(for: slides, groups: groups)
        #expect(names == ["Verse 1", "Verse 1", "Chorus", nil])
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: pid, slides: slides.map(\.content), sectionNames: names)))
        #expect(state.liveSectionName == nil && state.nextSectionName == nil)       // nothing is live
        state.apply(.trigger(index: 1))
        #expect(state.liveSectionName == "Verse 1" && state.nextSectionName == "Chorus")
        state.apply(.next); state.apply(.next)
        #expect(state.liveSectionName == nil && state.nextSectionName == nil)       // an ungrouped slide, and no next
        state.apply(.previous)
        #expect(state.liveSectionName == "Chorus")
        state.apply(.clear)
        #expect(state.liveSectionName == "Chorus")                                   // the place is kept while cleared, as the stage keeps its words
    }

    @Test func aDeckWithoutNamesReadsNilAndEqualsOneBuiltTheOldWay() {
        let slides = [SlideContent(primary: "a"), SlideContent(primary: "b")]
        let old = ShowDeck(presentationID: UUID(), slides: slides)
        #expect(old.sectionNames.isEmpty && old.sectionName(at: 0) == nil && old.sectionName(at: 5) == nil)
        var state = ShowState()
        state.apply(.load(old)); state.apply(.trigger(index: 0))
        #expect(state.liveSectionName == nil && state.nextSectionName == nil)
        // A deck shorter than its slides (or longer) never crashes.
        let ragged = ShowDeck(presentationID: old.presentationID, slides: slides, sectionNames: ["Only one", "Two", "Three"])
        #expect(ragged.sectionName(at: 1) == "Two" && ragged.sectionName(at: 2) == nil && ragged.sectionName(at: -1) == nil)
    }
}
