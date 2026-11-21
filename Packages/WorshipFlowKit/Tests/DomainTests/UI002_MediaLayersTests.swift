import Testing
import Foundation
@testable import Domain

@Suite struct UI002_MediaLayersTests {
    @Test func withoutForegroundKeepsTheBackgroundOnly() {
        var layers = MediaLayers()
        let bg = MediaSelection(assetID: UUID(), kind: .video, duration: 10)
        layers.setBackground(bg, at: 0)
        layers.startForeground(MediaSelection(assetID: UUID(), kind: .video, duration: 5), at: 0)
        #expect(layers.foreground != nil)
        let thumb = layers.withoutForeground
        #expect(thumb.foreground == nil)
        #expect(thumb.background?.selection == bg)
    }
}
