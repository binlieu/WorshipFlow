// UI-007c (SLIDE): what a text Fit, a text Background fill and a video object become in the scene the compositor draws. Objects that use none of
// the new fields compose exactly as before.
import Testing
import Foundation
@testable import Domain

@Suite struct UI007c_ObjectSceneTests {
    let frame = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3)
    let style = TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white)

    private func live(_ content: SlideContent) -> ShowState {
        var s = ShowState(); s.apply(.load(ShowDeck(presentationID: UUID(), slides: [content]))); s.apply(.trigger(index: 0)); return s
    }
    private func audience(_ objects: [SlideObject]) -> SceneDescription {
        SceneComposer.scene(for: .audience, state: live(SlideContent(primary: "Grace", objects: objects)), theme: .fullScreen, look: .standard, props: [])
    }
    private func text(_ fit: TextFit = .none, fill: ColorRGBA? = nil, opacity: Double = 1, hidden: Bool = false) -> SlideObject {
        SlideObject(frame: frame, opacity: opacity, isHidden: hidden,
                    content: .text(TextObject(text: "Hello", style: style, alignment: .leading, verticalAlignment: .top, fit: fit, backgroundFill: fill)))
    }

    // MARK: Text Fit

    @Test func aFittedTextBoxAsksTheCompositorToShrinkItDownToTheLyricFloorAndNoFurther() throws {
        let fitted = try #require(text(.shrinkToFit).drawableLayers.first)
        guard case .text(let layer) = fitted else { Issue.record("not text"); return }
        #expect(layer.fitFloor == Theme.fitFloor)
        guard case .text(let plain) = try #require(text().drawableLayers.first) else { Issue.record("not text"); return }
        #expect(plain.fitFloor == nil)
    }

    // MARK: Background fill

    @Test func aBackgroundFillIsABoxBehindTheWordsInTheSameFrameAndOpacity() throws {
        let colour = ColorRGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.6)
        let layers = text(fill: colour, opacity: 0.7).drawableLayers
        #expect(layers.count == 2)
        guard case .shape(let box) = layers[0], case .text(let words) = layers[1] else { Issue.record("wrong order"); return }
        #expect(box.shape == .rectangle && box.fill == colour && box.frame == frame && box.opacity == 0.7 && box.strokeWidth == 0)
        #expect(words.frame == frame && words.opacity == 0.7)
    }

    @Test func noFillMeansTheTextLayerAlone() {
        #expect(text().drawableLayers.count == 1)
    }

    @Test func aHiddenObjectDrawsNeitherItsFillNorItsWords() {
        #expect(text(fill: .white, hidden: true).drawableLayers.isEmpty)
        #expect(text(hidden: true).drawableLayer == nil)
    }

    @Test func aSlideWithNoNewValuesComposesExactlyAsBefore() {
        let objects = [
            SlideObject(frame: frame, content: .shape(ShapeObject(shape: .ellipse, fill: .white))),
            text(),
            SlideObject(frame: frame, content: .image(ImageObject(path: "/p.png", contentMode: .fill))),
        ]
        #expect(audience(objects).objectLayers == objects.map(\.sceneLayer))
    }

    @Test func theFillIsInTheSceneBeforeItsWordsAndKeepsTheOrderOfTheOthers() {
        let a = SlideObject(frame: frame, content: .shape(ShapeObject(shape: .rectangle, fill: .white)))
        let b = text(fill: .black)
        let c = SlideObject(frame: frame, content: .shape(ShapeObject(shape: .ellipse, fill: .white)))
        let layers = audience([a, b, c]).objectLayers
        #expect(layers.count == 4)
        #expect(layers[0] == a.sceneLayer && layers[3] == c.sceneLayer)
        if case .shape = layers[1], case .text = layers[2] {} else { Issue.record("fill must come right before its words") }
    }

    // MARK: Video object

    @Test func aVideoObjectIsALayerWithItsClipFrameOpacityLoopAndSound() throws {
        let media = UUID()
        let video = SlideObject(frame: frame, opacity: 0.5, content: .video(VideoObject(mediaID: media, loops: false, muted: false)))
        let layer = try #require(video.drawableLayer)
        #expect(layer == .video(VideoLayer(mediaID: media, frame: frame, opacity: 0.5, loops: false, muted: false)))
        #expect(layer == video.sceneLayer)
    }

    @Test func aHiddenVideoObjectIsNotAskedFor() {
        let video = SlideObject(frame: frame, isHidden: true, content: .video(VideoObject(mediaID: UUID())))
        #expect(video.drawableLayer == nil && video.drawableLayers.isEmpty)
        #expect(audience([video]).objectLayers.isEmpty)
    }

    @Test func aVideoObjectReachesTheAudienceSceneInItsPlaceAndNotAKeyedBroadcastOne() {
        let media = UUID()
        let shape = SlideObject(frame: frame, content: .shape(ShapeObject(shape: .rectangle, fill: .white)))
        let video = SlideObject(frame: frame, content: .video(VideoObject(mediaID: media)))
        let scene = audience([shape, video])
        #expect(scene.objectLayers.count == 2)
        #expect(scene.objectLayers[1] == .video(VideoLayer(mediaID: media, frame: frame, opacity: 1, loops: true, muted: true)))
        #expect(scene.videoObjectLayers.map(\.mediaID) == [media])
        let state = live(SlideContent(primary: "Grace", objects: [shape, video]))
        let keyed = SceneComposer.scene(for: .broadcast, state: state, theme: Theme.builtIn.first { $0.background == .transparent } ?? .fullScreen, look: .standard, props: [])
        if keyed.backgroundColor == .clear { #expect(keyed.objectLayers.isEmpty && keyed.videoObjectLayers.isEmpty) }
    }

    @Test func theSceneEncodesAndDecodesItsVideoLayersAndAnOldSceneStillDecodes() throws {
        let video = VideoLayer(mediaID: UUID(), frame: frame, opacity: 0.8, loops: true, muted: true)
        var scene = SceneDescription(backgroundColor: .black, textLayers: [])
        scene.objectLayers = [.video(video)]
        let decoded = try JSONDecoder().decode(SceneDescription.self, from: JSONEncoder().encode(scene))
        #expect(decoded == scene)
        var old = SceneDescription(backgroundColor: .black, textLayers: [])
        old.objectLayers = [.shape(ShapeLayer(shape: .rectangle, fill: .white, frame: frame))]
        #expect(try JSONDecoder().decode(SceneDescription.self, from: JSONEncoder().encode(old)) == old)
    }

    // MARK: Posters (a still in the place of a video, for the editor and the thumbnails)

    @Test func aPosterTakesTheVideosPlaceAsAPictureInItsFrameAndOpacity() throws {
        let media = UUID(), other = UUID()
        var scene = SceneDescription(backgroundColor: .black, textLayers: [])
        scene.objectLayers = [
            .shape(ShapeLayer(shape: .rectangle, fill: .white, frame: .full)),
            .video(VideoLayer(mediaID: media, frame: frame, opacity: 0.5, loops: true, muted: true)),
            .video(VideoLayer(mediaID: other, frame: frame, opacity: 1, loops: true, muted: true)),
        ]
        let shown = scene.replacingVideoObjects { $0 == media ? "/posters/a.jpg" : nil }
        #expect(shown.objectLayers.count == 2)                       // the clip with no poster draws nothing
        #expect(shown.objectLayers[0] == scene.objectLayers[0])
        #expect(shown.objectLayers[1] == .image(ImageLayer(path: "/posters/a.jpg", frame: frame, opacity: 0.5, contentMode: .fill)))
        #expect(shown.videoObjectLayers.isEmpty)
    }

    @Test func replacingVideosInASceneWithNoneChangesNothing() {
        var scene = SceneDescription(backgroundColor: .black, textLayers: [])
        scene.objectLayers = [.shape(ShapeLayer(shape: .rectangle, fill: .white, frame: .full))]
        #expect(scene.replacingVideoObjects { _ in "/x" } == scene)
    }
}
