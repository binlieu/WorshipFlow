// OUT-003: extra composition checks beyond the coordinator's acceptance tests.
import Testing
import Foundation
@testable import Domain

@Suite struct ThemeAndLookExtraTests {
    func liveState() -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "One", secondary: "Một")])))
        s.apply(.trigger(index: 0))
        return s
    }

    @Test func builtInThemeIDsAreStableAcrossProcesses() {
        // Stored references to built-in themes must keep resolving after a relaunch: pin the literal values.
        #expect(Theme.fullScreen.id.uuidString == "57465448-454D-4501-8000-000000000001")
        #expect(Theme.lowerThird.id.uuidString == "57465448-454D-4502-8000-000000000002")
    }

    @Test func builtInThemesComeFromTheStyles() {
        let s = SceneStyles.standard
        // UI-005h: the built-in themes are the design's looks; the earlier ones, which come from the styles, are the Classic themes (was: Theme.fullScreen, Theme.lowerThird)
        #expect(Theme.classicFullScreen.primary.style == s.audiencePrimary && Theme.classicFullScreen.primary.frame == s.audiencePrimaryFrame)
        #expect(Theme.classicLowerThird.secondary?.style == s.broadcastSecondary)
        #expect(Theme.mediaFallbackColor == s.audienceBackground)
    }

    @Test func legacyEntryPointStillHonoursCustomStyles() {
        var styles = SceneStyles()
        styles.audiencePrimary.fontSize = 33
        let scene = SceneComposer.scene(for: .audience, state: liveState(), styles: styles)
        #expect(scene.textLayers.first?.style.fontSize == 33)
    }

    @Test func hiddenBackgroundKeepsABroadcastTransparent() {
        let look = ScreenLook(themeID: nil, visibleLayers: [.slide])
        let scene = SceneComposer.scene(for: .broadcast, state: liveState(), theme: .lowerThird, look: look, props: [])
        #expect(scene.backgroundColor.alpha == 0 && scene.textLayers.count == 2)
    }

    @Test func stoppedBroadcastIsTransparentAndEmpty() {
        var s = liveState(); s.apply(.stop)
        let logo = Prop(name: "Logo", imagePath: "/tmp/l.png", frame: .full)
        let scene = SceneComposer.scene(for: .broadcast, state: s, theme: .lowerThird, look: .standard, props: [logo])
        #expect(scene.backgroundColor.alpha == 0 && scene.textLayers.isEmpty && scene.overlayImages.isEmpty)
    }

    @Test func themeBlockVerticalAlignmentIsUsed() {
        let scene = SceneComposer.scene(for: .audience, state: liveState(), theme: .fullScreen, look: .standard, props: [])
        #expect(scene.textLayers.first?.verticalAlignment == .bottom && scene.textLayers.last?.verticalAlignment == .top)
    }

    @Test func propOpacityIsClampedInTheLayer() {
        let p = Prop(name: "x", imagePath: "/tmp/x.png", frame: .full, opacity: 3)
        #expect(p.imageLayer.opacity == 1)
    }
}
