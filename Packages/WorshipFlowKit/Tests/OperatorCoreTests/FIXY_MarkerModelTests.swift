// FIX-Y items 5 and 6 (MEDIA, CUE-33; REVIEW-5 L8, L10): a marker's actions are decoded when its list loads or changes, not on every observer tick and
// every view body; and a list read requested while the first read of that clip is still in flight is not dropped.
import Testing
import Foundation
import CueEngine
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXY_MarkerModelTests {
    @Test func actionsAreDecodedOnceWhenTheListLoadsNotOnEveryLookOrTick() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip()
        var ids: [UUID] = []
        for t in [1.0, 2, 3] {
            let m = try #require(await rig.markers.add(to: clip.id, at: t))
            #expect(await rig.markers.setActions([.stopForeground], for: m.id) == nil)
            ids.append(m.id)
        }
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.playForeground(clip.id)
        let before = rig.markers.decodes
        for _ in 0..<40 { rig.markers.tick() }                                      // the observer's 50 ms tick
        for id in ids { for _ in 0..<40 { _ = rig.markers.actions(of: id); _ = rig.markers.actionsAreUnreadable(id) } }    // view bodies
        #expect(rig.markers.decodes == before)
        #expect(ids.allSatisfy { rig.markers.actions(of: $0) == [.stopForeground] })
    }

    @Test func aChangedMarkerIsReadAgainWhenItsListReloads() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip()
        let m = try #require(await rig.markers.add(to: clip.id, at: 3))
        #expect(await rig.markers.setActions([.stopForeground], for: m.id) == nil)
        #expect(rig.markers.actions(of: m.id) == [.stopForeground])
        #expect(await rig.markers.setActions([], for: m.id) == nil)
        #expect(rig.markers.actions(of: m.id).isEmpty)
        let text = try #require(MarkerActions.encode([.stopForeground]))
        try await rig.media.store.setMediaMarkerActions(id: m.id, actions: text)                  // changed in the library behind the model's back
        await rig.markers.load(clip.id)
        #expect(rig.markers.actions(of: m.id) == [.stopForeground] && !rig.markers.actionsAreUnreadable(m.id))
    }

    @Test func aReadAskedForWhileTheFirstReadIsInFlightIsNotDropped() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip()
        let first = Task { await rig.markers.load(clip.id) }                         // the first read of this clip, started and waiting on the library
        await Task.yield()
        #expect(rig.markers.readsStarted == 1 && rig.markers.markers(for: clip.id).isEmpty)
        await rig.markers.load(clip.id)                                              // what Add does after its insert: asked for before the first read is back
        await first.value
        #expect(rig.markers.readsStarted == 2)                                       // the second request was not thrown away
    }
}
