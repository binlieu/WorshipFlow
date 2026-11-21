// OUT-003 / SLIDE-002 acceptance tests: themes, alternate themes per screen, Looks and props
// (PRES-06, SCRN-08, SCRN-09, MEDIA-08). Owned by the coordinator: do not modify.
import Testing
import Foundation
@testable import Domain

@Suite struct ThemeAndLookTests {
    func liveState() -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [
            SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay"),
            SlideContent(primary: "That saved a wretch like me", secondary: "Đã cứu vớt tôi"),
        ])))
        s.apply(.trigger(index: 0))
        return s
    }
    let logo = Prop(id: UUID(), name: "Logo", imagePath: "/tmp/logo.png",
                    frame: NormalizedRect(x: 0.86, y: 0.04, width: 0.1, height: 0.1), opacity: 0.9, isOn: true)
    func texts(_ s: SceneDescription) -> [String] { s.textLayers.map(\.text) }

    // MARK: Themes (PRES-06)

    @Test func builtInThemesExistWithStableIDs() {
        #expect(Theme.fullScreen.id != Theme.lowerThird.id)
        #expect(Theme.fullScreen.id == Theme.fullScreen.id)
        #expect(Theme.builtIn.map(\.id).contains(Theme.fullScreen.id))
        #expect(Theme.builtIn.map(\.id).contains(Theme.lowerThird.id))
        #expect(Theme.lowerThird.background == .transparent)
        #expect(Theme.lowerThird.primary.frame.y >= 0.6)
        #expect(Theme.fullScreen.background == .media)
    }

    @Test func themeControlsStyleAndPlacement() {
        var theme = Theme.fullScreen
        theme.primary.style.fontSize = 120
        theme.primary.frame = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.3)
        theme.primary.alignment = .leading
        let scene = SceneComposer.scene(for: .audience, state: liveState(), theme: theme, look: .standard, props: [])
        let primary = scene.textLayers.first { $0.text.hasPrefix("Amazing") }
        #expect(primary?.style.fontSize == 120)
        #expect(primary?.frame == theme.primary.frame)
        #expect(primary?.alignment == .leading)
    }

    /// PRES-06: one theme edit restyles every slide.
    @Test func editingAThemeRestylesEverySlide() {
        var theme = Theme.fullScreen
        theme.primary.style.color = ColorRGBA(red: 1, green: 0.9, blue: 0.2)
        var s = liveState()
        let first = SceneComposer.scene(for: .audience, state: s, theme: theme, look: .standard, props: [])
        s.apply(.next)
        let second = SceneComposer.scene(for: .audience, state: s, theme: theme, look: .standard, props: [])
        #expect(first.textLayers.first?.style.color == theme.primary.style.color)
        #expect(second.textLayers.first?.style.color == theme.primary.style.color)
    }

    @Test func themeWithoutSecondBlockHidesTheSecondLanguage() {
        var theme = Theme.fullScreen
        theme.secondary = nil
        let scene = SceneComposer.scene(for: .audience, state: liveState(), theme: theme, look: .standard, props: [])
        #expect(texts(scene) == ["Amazing grace, how sweet the sound"])
    }

    @Test func themeBackgrounds() {
        var theme = Theme.fullScreen
        theme.background = .color(ColorRGBA(red: 0.2, green: 0, blue: 0))
        var scene = SceneComposer.scene(for: .audience, state: liveState(), theme: theme, look: .standard, props: [])
        #expect(scene.showsVideo == false && scene.backgroundColor == ColorRGBA(red: 0.2, green: 0, blue: 0) && scene.backgroundImage == nil)
        theme.background = .image(path: "/tmp/bg.jpg")
        scene = SceneComposer.scene(for: .audience, state: liveState(), theme: theme, look: .standard, props: [])
        #expect(scene.backgroundImage?.path == "/tmp/bg.jpg" && scene.backgroundImage?.frame == .full && scene.backgroundImage?.contentMode == .fill)
        #expect(scene.showsVideo == false)
        theme.background = .transparent
        scene = SceneComposer.scene(for: .audience, state: liveState(), theme: theme, look: .standard, props: [])
        #expect(scene.backgroundColor.alpha == 0 && scene.showsVideo == false)
        theme.background = .media
        scene = SceneComposer.scene(for: .audience, state: liveState(), theme: theme, look: .standard, props: [])
        #expect(scene.showsVideo)
    }

    // MARK: Alternate themes (SCRN-09)

    /// The same slide is full-screen on one screen and a lower third on another, from one state.
    @Test func sameSlideTwoThemes() {
        let s = liveState()
        let sanctuary = SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: [])
        let stream = SceneComposer.scene(for: .audience, state: s, theme: .lowerThird, look: .standard, props: [])
        #expect(texts(sanctuary) == texts(stream))
        #expect(sanctuary.textLayers.first?.frame != stream.textLayers.first?.frame)
        #expect(stream.textLayers.allSatisfy { $0.frame.y >= 0.6 })
        #expect(stream.backgroundColor.alpha == 0)
    }

    @Test func themeResolutionOrder() {
        var custom = Theme.fullScreen; custom = Theme(id: UUID(), name: "Easter", background: custom.background, primary: custom.primary, secondary: custom.secondary)
        var screenTheme = Theme.lowerThird; screenTheme = Theme(id: UUID(), name: "Stream", background: screenTheme.background, primary: screenTheme.primary, secondary: screenTheme.secondary)
        let all = Theme.builtIn + [custom, screenTheme]
        // The screen's Look wins over the presentation's theme, which wins over the role default.
        #expect(ThemeResolver.theme(for: .audience, lookThemeID: screenTheme.id, presentationThemeID: custom.id, themes: all).id == screenTheme.id)
        #expect(ThemeResolver.theme(for: .audience, lookThemeID: nil, presentationThemeID: custom.id, themes: all).id == custom.id)
        #expect(ThemeResolver.theme(for: .audience, lookThemeID: nil, presentationThemeID: nil, themes: all).id == Theme.fullScreen.id)
        #expect(ThemeResolver.theme(for: .broadcast, lookThemeID: nil, presentationThemeID: nil, themes: all).id == Theme.lowerThird.id)
        // A broadcast screen never inherits a presentation's full-screen theme: only its own Look can override the lower third.
        #expect(ThemeResolver.theme(for: .broadcast, lookThemeID: nil, presentationThemeID: custom.id, themes: all).id == Theme.lowerThird.id)
        // Unknown ids fall back rather than fail.
        #expect(ThemeResolver.theme(for: .audience, lookThemeID: UUID(), presentationThemeID: UUID(), themes: all).id == Theme.fullScreen.id)
    }

    // MARK: Looks (SCRN-08)

    @Test func standardLookShowsEveryLayer() {
        #expect(ScreenLook.standard.visibleLayers == Set(LayerKind.allCases))
        #expect(ScreenLook.standard.themeID == nil)
    }

    @Test func lookHidesLayersIndependently() {
        let s = liveState()
        let noSlide = SceneComposer.scene(for: .audience, state: s, theme: .fullScreen,
                                          look: ScreenLook(themeID: nil, visibleLayers: [.background, .props]), props: [logo])
        #expect(noSlide.textLayers.isEmpty && noSlide.showsVideo && noSlide.overlayImages.count == 1)
        let noBackground = SceneComposer.scene(for: .audience, state: s, theme: .fullScreen,
                                               look: ScreenLook(themeID: nil, visibleLayers: [.slide]), props: [logo])
        #expect(noBackground.showsVideo == false && noBackground.backgroundImage == nil)
        #expect(noBackground.backgroundColor == .black)
        #expect(noBackground.textLayers.count == 2 && noBackground.overlayImages.isEmpty)
    }

    @Test func lookGivesEachScreenItsOwnSettings() {
        let sanctuary = UUID(), stream = UUID(), other = UUID()
        let look = Look(id: UUID(), name: "Worship", screens: [
            sanctuary: ScreenLook(themeID: nil, visibleLayers: [.background, .slide]),
            stream: ScreenLook(themeID: Theme.lowerThird.id, visibleLayers: [.slide, .props]),
        ])
        #expect(look.screenLook(for: sanctuary).visibleLayers == [.background, .slide])
        #expect(look.screenLook(for: stream).themeID == Theme.lowerThird.id)
        #expect(look.screenLook(for: other) == .standard)     // a screen the Look does not mention shows everything
    }

    @Test func looksAndThemesRoundTripThroughCodable() throws {
        let look = Look(id: UUID(), name: "Worship", screens: [UUID(): ScreenLook(themeID: Theme.lowerThird.id, visibleLayers: [.slide])])
        #expect(try JSONDecoder().decode(Look.self, from: JSONEncoder().encode(look)) == look)
        var theme = Theme.fullScreen; theme.background = .image(path: "/tmp/bg.jpg")
        #expect(try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme)) == theme)
        #expect(try JSONDecoder().decode(Prop.self, from: JSONEncoder().encode(logo)) == logo)
    }

    // MARK: Props (MEDIA-08)

    @Test func propStaysAcrossSlideChangesAndClear() {
        var s = liveState()
        func overlays() -> [ImageLayer] {
            SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: [logo]).overlayImages
        }
        #expect(overlays() == [ImageLayer(path: "/tmp/logo.png", frame: logo.frame, opacity: 0.9, contentMode: .fit)])
        s.apply(.next)
        #expect(overlays().count == 1)
        s.apply(.clear)
        #expect(overlays().count == 1)        // Clear removes the slide, not the logo
        s.apply(.stop)
        #expect(overlays().isEmpty)
    }

    @Test func propThatIsOffIsNotDrawn() {
        var off = logo; off.isOn = false
        let scene = SceneComposer.scene(for: .audience, state: liveState(), theme: .fullScreen, look: .standard, props: [off, logo])
        #expect(scene.overlayImages.count == 1)
    }

    /// Props belong to audience and broadcast screens. The stage layout never shows them.
    @Test func stageIgnoresThemesLooksAndProps() {
        let s = liveState()
        let plain = SceneComposer.scene(for: .stage, state: s)
        let themed = SceneComposer.scene(for: .stage, state: s, theme: .lowerThird,
                                         look: ScreenLook(themeID: nil, visibleLayers: [.props]), props: [logo])
        #expect(themed == plain)
        #expect(themed.overlayImages.isEmpty)
    }

    @Test func broadcastWithPropsKeepsTransparency() {
        let scene = SceneComposer.scene(for: .broadcast, state: liveState(), theme: .lowerThird, look: .standard, props: [logo])
        #expect(scene.backgroundColor.alpha == 0 && scene.overlayImages.count == 1 && scene.showsVideo == false)
    }

    /// The earlier entry point still works and matches the role's default theme with the standard Look.
    @Test func legacyEntryPointMatchesDefaults() {
        let s = liveState()
        for role in [ScreenRole.audience, .broadcast] {
            let legacy = SceneComposer.scene(for: role, state: s)
            let explicit = SceneComposer.scene(for: role, state: s, theme: ThemeResolver.theme(for: role, lookThemeID: nil, presentationThemeID: nil, themes: Theme.builtIn), look: .standard, props: [])
            #expect(legacy == explicit)
        }
    }
}
