// STAGE-001a: extra persistence checks.
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct StageStoreExtraTests {
    @Test func blankNamesAndUnknownTimersAreRejected() async throws {
        let store = try LibraryStore.inMemory()
        await #expect(throws: StoreError.invalidName) {
            try await store.saveTimer(ShowTimer(id: UUID(), name: "  ", kind: .elapsed))
        }
        await #expect(throws: StoreError.notFound) { try await store.deleteTimer(id: UUID()) }
    }

    @Test func countdownToAndTimerElementsSurvive() async throws {
        let store = try LibraryStore.inMemory()
        let timer = ShowTimer(id: UUID(), name: "Starts", kind: .countdownTo(Date(timeIntervalSinceReferenceDate: 12345.5)))
        try await store.saveTimer(timer)
        var layout = StageLayout.standard
        layout = StageLayout(id: UUID(), name: "With timer", background: .black, elements: layout.elements + [
            StageElement(id: UUID(), kind: .timer(timer.id), frame: .full, style: layout.elements[0].style, alignment: .center),
        ])
        try await store.saveStageLayout(layout)
        #expect(try await store.timers() == [timer])
        #expect(try await store.stageLayouts() == [layout])
    }

    @Test func editingALayoutKeepsItsPlaceInTheList() async throws {
        let store = try LibraryStore.inMemory()
        let a = StageLayout(id: UUID(), name: "A", background: .black, elements: [])
        let b = StageLayout(id: UUID(), name: "B", background: .black, elements: [])
        try await store.saveStageLayout(a); try await store.saveStageLayout(b)
        var a2 = a; a2.name = "A2"
        try await store.saveStageLayout(a2)
        #expect(try await store.stageLayouts().map(\.name) == ["A2", "B"])
    }
}
