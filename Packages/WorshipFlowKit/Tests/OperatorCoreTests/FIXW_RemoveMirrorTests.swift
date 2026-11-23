// FIX-W item 2 (HW-002, SYS-015; REVIEW-5 M2): removing a mirror shifts every per-destination array, so the notes and chains of the mirrors
// that stay are still on their own destination.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct FIXW_RemoveMirrorTests {
    func profile() -> ScreenProfile {
        var p = ScreenProfile(name: "Broadcast", role: .broadcast,
                              destination: .sdi(deviceID: "d", connector: 1, keying: true, fillAlphaMode: .premultiplied),
                              mirrors: [.sdi(deviceID: "d", connector: 3, keying: true, fillAlphaMode: .premultiplied), .window])
        p.setConnectedNote("main fill", mirror: nil);   p.setConnectedKeyNote("main key", mirror: nil)
        p.setConnectedNote("first fill", mirror: 0);    p.setConnectedKeyNote("first key", mirror: 0)
        p.setConnectedNote("second fill", mirror: 1);   p.setConnectedKeyNote("second key", mirror: 1)
        p.setSignalChain([ChainNode(kind: .enclosure, label: "main box")], mirror: nil)
        p.setSignalChain([ChainNode(kind: .converter, label: "first box")], mirror: 0)
        p.setSignalChain([ChainNode(kind: .other, label: "second box")], mirror: 1)
        return p
    }

    @Test func removingTheFirstMirrorLeavesTheSecondWithItsOwnNotesAndChain() {
        let q = ScreenEditing.removingMirror(profile(), at: 0)
        #expect(q.mirrors == [.window])
        #expect(q.connectedNote(mirror: 0) == "second fill" && q.connectedKeyNote(mirror: 0) == "second key")
        #expect(q.signalChain(mirror: 0).map(\.label) == ["second box"])
        #expect(q.connectedNote(mirror: nil) == "main fill" && q.connectedKeyNote(mirror: nil) == "main key")
        #expect(q.signalChain(mirror: nil).map(\.label) == ["main box"])
        #expect(q.connectedTo.count <= 2 && q.connectedToKey.count <= 2 && q.signalChains.count <= 2)    // nothing left past the end
    }

    @Test func removingTheLastMirrorDropsItsNotesAndChainAndTheRestStays() {
        let q = ScreenEditing.removingMirror(profile(), at: 1)
        #expect(q.mirrors.count == 1)
        #expect(q.connectedNote(mirror: 0) == "first fill" && q.connectedKeyNote(mirror: 0) == "first key")
        #expect(q.signalChain(mirror: 0).map(\.label) == ["first box"])
        #expect(q.connectedTo.count == 2 && q.connectedToKey.count == 2 && q.signalChains.count == 2)
    }

    @Test func aMirrorWithNoKeyNoteOrChainStillShiftsTheOthers() {
        var p = profile()
        p.connectedToKey = ["", "", "second key"]
        p.signalChains = [[], [], [ChainNode(kind: .other, label: "second box")]]
        let q = ScreenEditing.removingMirror(p, at: 0)
        #expect(q.connectedKeyNote(mirror: 0) == "second key" && q.signalChain(mirror: 0).map(\.label) == ["second box"])
    }

    @Test func removingTheOnlyMirrorEmptiesTheTailArraysAndAMissingIndexChangesNothing() {
        var p = profile(); p.mirrors = [.window]
        p.connectedTo = ["a", "b"]; p.connectedToKey = ["", "k"]; p.signalChains = [[], [ChainNode(kind: .other, label: "x")]]
        let q = ScreenEditing.removingMirror(p, at: 0)
        #expect(q.connectedToKey.isEmpty && q.signalChains.isEmpty && q.connectedTo == ["a"])
        let whole = profile()
        #expect(ScreenEditing.removingMirror(whole, at: 9) == whole)
    }
}
