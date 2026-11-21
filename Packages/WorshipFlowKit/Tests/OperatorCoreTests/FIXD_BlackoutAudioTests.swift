// FIX-D (coordinator decision): Blackout also mutes the foreground clip's sound while it is on and restores the previous level
// when it lifts. Model level: the app only passes the show state on.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXD_BlackoutAudioTests {
    private func live() throws -> MediaRig {
        let rig = try MediaRig()
        rig.model.showStateChanged(isLive: true)
        rig.audioChanges.removeAll()
        return rig
    }

    @Test func blackoutMutesTheClipAndLiftingItRestoresThePreviousLevel() throws {
        let rig = try live()
        rig.model.setVolume(0.8)
        rig.audioChanges.removeAll()
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        #expect(rig.audioChanges.count == 1 && rig.audioChanges[0].0 == 0.8 && rig.audioChanges[0].1 == true)
        #expect(rig.model.isMutedByBlackout)
        #expect(rig.model.isMuted == false && rig.model.volume == 0.8, "the operator's own settings are not changed")
        rig.model.showStateChanged(isLive: true, isBlackedOut: false)
        #expect(rig.audioChanges.count == 2 && rig.audioChanges[1].0 == 0.8 && rig.audioChanges[1].1 == false)
        #expect(!rig.model.isMutedByBlackout)
    }

    @Test func anOperatorMuteSurvivesBlackoutAndStaysAfterItLifts() throws {
        let rig = try live()
        rig.model.setMuted(true)
        rig.audioChanges.removeAll()
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        rig.model.showStateChanged(isLive: true, isBlackedOut: false)
        #expect(rig.audioChanges.map { $0.1 } == [true, true])
        #expect(rig.model.isMuted)
    }

    @Test func aVolumeOrMuteChangedDuringBlackoutStaysSilentAndAppliesWhenItLifts() throws {
        let rig = try live()
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        rig.model.setVolume(0.2)
        rig.model.setMuted(true)
        rig.model.setMuted(false)
        #expect(rig.audioChanges.allSatisfy { $0.1 == true }, "\(rig.audioChanges)")
        rig.audioChanges.removeAll()
        rig.model.showStateChanged(isLive: true, isBlackedOut: false)
        #expect(rig.audioChanges.count == 1 && rig.audioChanges[0].0 == 0.2 && rig.audioChanges[0].1 == false)
    }

    @Test func aClipStartedDuringBlackoutStartsSilent() async throws {
        let rig = try live()
        let clip = await rig.add("clip.mov")
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        rig.model.playForeground(clip.id)
        #expect(rig.model.layers.foreground != nil)
        #expect(rig.audioChanges.last?.1 == true, "the level the player is given is muted")
    }

    @Test func stopEndsBlackoutAndGivesTheSoundBackForTheNextClip() async throws {
        let rig = try live()
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        rig.audioChanges.removeAll()
        rig.model.showStateChanged(isLive: false, isBlackedOut: false)
        #expect(rig.audioChanges.last?.1 == false)
        #expect(!rig.model.isMutedByBlackout)
    }

    @Test func nothingIsSentWhenBlackoutDidNotChange() throws {
        let rig = try live()
        rig.model.showStateChanged(isLive: true, isBlackedOut: false)
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        #expect(rig.audioChanges.count == 1)
    }

    @Test func theWorkspaceBlackoutDrivesTheMuteAsTheAppWiresIt() async throws {
        let rig = try MediaRig()
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store)
        // exactly what the app does on every change of the show
        workspace.onShowChange = { state in rig.model.showStateChanged(isLive: !state.isStopped, isBlackedOut: state.isBlackedOut) }
        await workspace.load()
        let p = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 1))
        await workspace.openPresentation(p.id)
        await workspace.goLive()
        rig.audioChanges.removeAll()
        workspace.blackout()
        #expect(rig.audioChanges.last?.1 == true)
        workspace.blackout()
        #expect(rig.audioChanges.last?.1 == false)
        workspace.blackout()
        workspace.stop()
        #expect(rig.audioChanges.last?.1 == false, "Stop ends Blackout, so the sound is back")
    }
}
