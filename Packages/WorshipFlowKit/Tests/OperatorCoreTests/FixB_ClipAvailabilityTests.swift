// FIX-B (coordinator note): a foreground clip whose player failed or stalled ends, so the words come back.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct ClipAvailabilityTests {
    private func playing() async throws -> (MediaRig, MediaAsset) {
        let rig = try MediaRig()
        let clip = await rig.add("sermon.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        #expect(rig.model.layers.foreground != nil)
        return (rig, clip)
    }

    @Test func aFailedForegroundClipEndsAndTheErrorNamesTheFile() async throws {
        let (rig, clip) = try await playing()
        rig.model.availabilityChanged(clip.id, .failed("The file is damaged."))
        #expect(rig.model.layers.foreground == nil)
        let message = try #require(rig.model.lastError)
        #expect(message.contains("sermon") && message.contains("damaged"))
    }

    @Test func aStalledForegroundClipEndsToo() async throws {
        let (rig, clip) = try await playing()
        rig.model.availabilityChanged(clip.id, .stalled)
        #expect(rig.model.layers.foreground == nil)
        #expect(rig.model.lastError?.contains("sermon") == true)
    }

    @Test func startingIsNotAFailure() async throws {
        let (rig, clip) = try await playing()
        for state: ClipAvailability in [.notOpen, .starting, .delivering] {
            rig.model.availabilityChanged(clip.id, state)
            #expect(rig.model.layers.foreground != nil && rig.model.lastError == nil, "\(state)")
        }
    }

    @Test func aFailedBackgroundReportsAndFallsBackToTheTheme() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.setBackground(loop.id)
        rig.model.availabilityChanged(loop.id, .failed("Cannot decode."))
        #expect(rig.model.layers.background == nil)
        #expect(rig.model.lastError?.contains("loop") == true)
        #expect(rig.layerChanges.last?.background == nil)
    }

    @Test func aReportAboutAnotherAssetChangesNothing() async throws {
        let (rig, _) = try await playing()
        rig.model.availabilityChanged(UUID(), .failed("x"))
        #expect(rig.model.layers.foreground != nil && rig.model.lastError == nil)
    }
}
