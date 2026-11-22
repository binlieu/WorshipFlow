// FIX-T item 3 (M1 audit): `HotFolderModel.relocate` found the folder's position, suspended to save it, and wrote through the old position.
// A folder removed during the save shifted the list: the write trapped or changed another folder. It finds the folder again by id.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXT_HotFolderIndexTests {
    @Test func aFolderRemovedWhileAnotherIsBeingPointedAtItsNewPlaceDoesNotShiftTheWrite() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a", ["one.mov": 100])
        r.fs.create("/hot/b", ["two.mov": 100])
        r.fs.create("/hot/moved", ["two.mov": 100])
        let a = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        let b = try #require(await r.model.add(path: "/hot/b", bookmark: nil))
        let move = Task { await r.model.relocate(b.id, to: "/hot/moved", bookmark: nil) }
        await r.model.remove(a.id)
        await move.value
        #expect(r.model.state(of: a.id) == nil)
        let state = try #require(r.model.state(of: b.id))
        #expect(state.folder.path == "/hot/moved")
        #expect(r.model.folders.count == 1)
    }

    @Test func aFolderRemovedWhileItIsBeingPointedAtANewPlaceIsNotBroughtBack() async throws {
        let r = try ScriptedRig()
        r.fs.create("/hot/a", ["one.mov": 100])
        r.fs.create("/hot/moved", ["one.mov": 100])
        let a = try #require(await r.model.add(path: "/hot/a", bookmark: nil))
        let move = Task { await r.model.relocate(a.id, to: "/hot/moved", bookmark: nil) }
        await r.model.remove(a.id)
        await move.value
        #expect(r.model.state(of: a.id) == nil)
        #expect(r.model.folders.isEmpty)
    }
}
