// SLIDE-001b: new stage layout elements are placed in free space (written by the implementer).
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct StageFreeSpaceTests {
    func emptyLayout() async throws -> (StageModel, StageLayout) {
        let model = StageModel(store: try LibraryStore.inMemory())
        await model.load()
        let layout = try #require(model.createLayout(name: "Free"))
        for e in layout.elements { model.removeElement(e.id, from: layout.id) }
        return (model, try #require(model.layout(withID: layout.id)))
    }

    func frames(_ model: StageModel, _ id: UUID) -> [NormalizedRect] { model.layout(withID: id)?.elements.map(\.frame) ?? [] }

    @Test func aFreeDefaultPlaceIsKept() async throws {
        let (model, layout) = try await emptyLayout()
        let first = try #require(model.addElement(.message, to: layout.id))
        let expected = try #require(StageEditing.newElement(.message, timerID: nil)).frame
        #expect(model.layout(withID: layout.id)?.elements.first { $0.id == first }?.frame == expected)
    }

    @Test func aSecondElementDoesNotLandOnTheFirst() async throws {
        let (model, layout) = try await emptyLayout()
        model.addElement(.currentSlide, to: layout.id)
        model.addElement(.message, to: layout.id)
        model.addElement(.message, to: layout.id)         // the default place of this one is taken by the one before
        let all = frames(model, layout.id)
        #expect(all.count == 3)
        for i in all.indices { for j in all.indices where i < j { #expect(FreeSpace.overlap(all[i], all[j]) == 0, "\(i) \(j)") } }
        for f in all { #expect(f.x >= 0 && f.y >= 0 && f.x + f.width <= 1.0000001 && f.y + f.height <= 1.0000001) }
    }

    @Test func aFullLayoutStillGetsAnElementOnScreen() async throws {
        let (model, layout) = try await emptyLayout()
        for _ in 0..<12 { model.addElement(.notes, to: layout.id) }
        let all = frames(model, layout.id)
        #expect(all.count == 12)
        for f in all {
            #expect(f.x >= 0 && f.y >= 0 && f.x + f.width <= 1.0000001 && f.y + f.height <= 1.0000001)
            #expect(f.width >= StageElement.minimumSize && f.height >= StageElement.minimumSize)
        }
    }
}
