// FIX-Y item 8 (SC-25, SC-31; REVIEW-5 L14): a typed key note or signal-chain label is committed to the screen it was typed for, also when the field goes
// away with focus still in it (the operator clicked another screen); the three triggers never write the same text twice.
import Testing
import Foundation
@testable import OperatorCore

@Suite struct FIXY_NoteDraftTests {
    @Test func aDraftThatDiffersFromTheStoredValueIsWritten() {
        #expect(NoteDraft.pending(draft: "to ATEM 5", value: "", written: nil) == "to ATEM 5")
    }

    @Test func aDraftEqualToTheStoredValueWritesNothing() {
        #expect(NoteDraft.pending(draft: "same", value: "same", written: nil) == nil)
    }

    @Test func aDraftAlreadyWrittenIsNotWrittenAgainByTheLaterTrigger() {
        #expect(NoteDraft.pending(draft: "to ATEM 5", value: "", written: "to ATEM 5") == nil)        // focus lost wrote it; the field then goes away
    }

    @Test func aDraftEditedAfterAWriteIsWrittenAgain() {
        #expect(NoteDraft.pending(draft: "to ATEM 6", value: "", written: "to ATEM 5") == "to ATEM 6")
    }

    @Test func clearingTheNoteIsAWrite() {
        #expect(NoteDraft.pending(draft: "", value: "old", written: nil) == "")
    }

    @Test func theFieldCommitsWhenItGoesAwayAsWellAsOnReturnAndWhenLeft() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let text = try String(contentsOf: url.appendingPathComponent("App/Sources/ScreensNotes.swift"), encoding: .utf8)
        let field = try #require(text.range(of: "private struct CommitField: View"))
        let body = String(text[field.lowerBound...])
        #expect(body.contains(".onSubmit") && body.contains(".onDisappear"), "the draft is lost when the screen selection changes while the field has focus")
        #expect(body.contains("NoteDraft.pending"))
    }
}
