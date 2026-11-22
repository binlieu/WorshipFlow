// FIX-N item 9: a slide copied into another presentation (its content handed to `appendSlide`) carries its own text frames, and what is read back is
// what was written.
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct FIXN_CopiedSlideFramesTests {
    @Test func aCopiedSlidesContentCarriesItsFrames() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let a = try await store.createPresentation(in: lib.id, title: "A", kind: .song)
        let b = try await store.createPresentation(in: lib.id, title: "B", kind: .song)
        let frames = SlideTextFrames(primary: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25), secondary: NormalizedRect(x: 0.2, y: 0.6, width: 0.6, height: 0.2))
        let original = try await store.appendSlide(to: a.id, content: SlideContent(primary: "one", secondary: "một", textFrames: frames))
        let copy = try await store.appendSlide(to: b.id, content: original.content)
        #expect(copy.id != original.id)
        #expect(copy.content.textFrames == frames)
        #expect(try await store.slides(of: b.id).first?.content.textFrames == frames)
        #expect(try await store.slides(of: a.id).first?.content.textFrames == frames, "the original is unchanged")
    }
}
