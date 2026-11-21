// UI-005b item 5: a prop is drawn only on the roles it is targeted to, picture props and text props alike, and a text prop's words
// reach the scene as the same `TextLayer` the slides use (so Vietnamese marks go through the same text path).
import Testing
import Foundation
@testable import Domain

@Suite struct UI005b_PropTargetTests {
    let frame = NormalizedRect(x: 0.8, y: 0.05, width: 0.15, height: 0.1)
    func live(_ words: String = "Words on the slide") -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: words)])))
        s.apply(.trigger(index: 0))
        return s
    }
    func logo(_ targets: Set<ScreenRole>, on: Bool = true) -> Prop {
        Prop(name: "Logo", imagePath: "/p/logo.png", frame: frame, isOn: on, targets: targets)
    }
    func strap(_ targets: Set<ScreenRole>, text: String = "Ân điển lạ lùng", on: Bool = true) -> Prop {
        Prop(name: "Strap", imagePath: "", frame: frame, isOn: on, targets: targets, kind: .text, text: TextPropSpec(text: text))
    }
    func scene(_ role: ScreenRole, _ props: [Prop], look: ScreenLook = .standard, state: ShowState? = nil) -> SceneDescription {
        SceneComposer.scene(for: role, state: state ?? live(), theme: Theme.makeFullScreen(styles: .standard),
                            look: look, props: props)
    }
    func overlays(_ role: ScreenRole, _ props: [Prop]) -> [String] { scene(role, props).overlayImages.map(\.path) }
    func words(_ role: ScreenRole, _ props: [Prop]) -> [String] { scene(role, props).textLayers.map(\.text) }

    @Test func aPictureTargetedToAudienceAndBroadcastIsOnNeitherOtherRole() {
        let p = [logo([.audience, .broadcast])]
        #expect(overlays(.audience, p) == ["/p/logo.png"] && overlays(.broadcast, p) == ["/p/logo.png"])
        #expect(overlays(.stage, p).isEmpty)
    }

    @Test func aPropTargetedToStageOnlyIsAbsentFromAudienceAndBroadcast() {
        let p = [logo([.stage]), strap([.stage])]
        for role in [ScreenRole.audience, .broadcast] {
            #expect(overlays(role, p).isEmpty)
            #expect(!words(role, p).contains("Ân điển lạ lùng"))
            #expect(scene(role, p).textLayers.map(\.text) == ["Words on the slide"])        // only the slide's own words
        }
        #expect(overlays(.stage, p) == ["/p/logo.png"])
        #expect(words(.stage, p).contains("Ân điển lạ lùng"))
    }

    @Test func aPropWithNoTargetsIsOnNoScreen() {
        let p = [logo([]), strap([])]
        for role in ScreenRole.allCases { #expect(overlays(role, p).isEmpty && !words(role, p).contains("Ân điển lạ lùng")) }
    }

    @Test func offAndHiddenLayerStillWinOverTargets() {
        let off = [logo(Set(ScreenRole.allCases), on: false), strap(Set(ScreenRole.allCases), on: false)]
        for role in ScreenRole.allCases { #expect(overlays(role, off).isEmpty && !words(role, off).contains("Ân điển lạ lùng")) }
        let hidden = ScreenLook(visibleLayers: [.slide, .background])         // the Look hides the props layer on this screen
        let on = [logo(Set(ScreenRole.allCases)), strap(Set(ScreenRole.allCases))]
        for role in ScreenRole.allCases {
            #expect(scene(role, on, look: hidden).overlayImages.isEmpty)
            #expect(!scene(role, on, look: hidden).textLayers.map(\.text).contains("Ân điển lạ lùng"))
        }
    }

    @Test func noPropIsDrawnWhileStoppedOrBlackedOut() {
        let all = [logo(Set(ScreenRole.allCases)), strap(Set(ScreenRole.allCases))]
        var blacked = live()
        blacked.apply(.blackout)
        for role in ScreenRole.allCases {
            #expect(scene(role, all, state: ShowState()).overlayImages.isEmpty && scene(role, all, state: ShowState()).textLayers.isEmpty)
            #expect(scene(role, all, state: blacked).overlayImages.isEmpty && !scene(role, all, state: blacked).textLayers.map(\.text).contains("Ân điển lạ lùng"))
        }
    }

    @Test func textPropWordsKeepTheirVietnameseMarksAndUseTheSameLayerTypeAsLyrics() throws {
        let diacritics = "Tôn Vinh Chúa — Ễ Ậ Ở Ỗ Ẵ ỷ ự"
        let p = [strap([.audience], text: diacritics)]
        let layer = try #require(scene(.audience, p).textLayers.last)
        #expect(layer.text == diacritics && layer.text.unicodeScalars.map(\.value) == diacritics.unicodeScalars.map(\.value))
        let slideLayer = try #require(scene(.audience, p).textLayers.first)
        #expect(type(of: layer) == type(of: slideLayer))                           // one text path for both
        #expect(layer.style.fontName == "Helvetica Neue" && layer.style.fontSize == 48)
        #expect(layer.alignment == .leading && layer.verticalAlignment == .bottom)  // the default anchor, bottom left
    }

    @Test func theAnchorDecidesTheBoxAndTheAlignment() {
        let a = PropAnchor.topRight
        #expect(a.horizontal == .trailing && a.vertical == .top)
        #expect(a.frame.x + a.frame.width <= 1 && a.frame.x > 0.3 && a.frame.y < 0.1)
        for anchor in PropAnchor.allCases {
            let f = anchor.frame
            #expect(f.x >= 0 && f.y >= 0 && f.x + f.width <= 1.0001 && f.y + f.height <= 1.0001)
        }
        #expect(PropAnchor.center.frame.x == 0.2 && PropAnchor.center.horizontal == .center)
    }

    @Test func colourAndSizeAreReadSafely() {
        #expect(TextPropSpec(text: "x", colorHex: "#FFD17B").color == ColorRGBA(red: 1, green: Double(0xD1) / 255, blue: Double(0x7B) / 255))
        #expect(TextPropSpec(text: "x", colorHex: "not a colour").color == .white)
        #expect(TextPropSpec(text: "x", fontSize: 4).fontSize == 12 && TextPropSpec(text: "x", fontSize: 9_000).fontSize == 200)
        #expect(TextPropSpec(text: "x", fontSize: .nan).fontSize == 48)
    }

    @Test func aTextPropWithNoWordsDrawsNothing() {
        #expect(strap([.audience], text: "   ").textLayer == nil)
        #expect(logo([.audience]).textLayer == nil)
    }

    @Test func propsMadeBeforeV12DecodeWithTheirOldReach() throws {
        let old = #"{"id":"6F2C3E1A-1111-4A2B-8C3D-000000000001","name":"Logo","imagePath":"/x.png","frame":{"x":0,"y":0,"width":1,"height":1},"opacity":1,"isOn":true}"#
        let prop = try JSONDecoder().decode(Prop.self, from: Data(old.utf8))
        #expect(prop.targets == [.audience, .broadcast] && prop.kind == .image && prop.text == nil)
    }
}
