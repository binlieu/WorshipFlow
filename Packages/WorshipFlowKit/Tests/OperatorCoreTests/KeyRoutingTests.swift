// APP-001 / KI-021: the "should this key go to the transport?" decision.
import Testing
@testable import OperatorCore

@Suite struct KeyRoutingTests {
    @Test func transportKeysReachTheShowWhenNothingIsBeingTyped() {
        let expected: [(KeyboardKey, TransportCommand)] = [
            (.returnKey, .goLive), (.keypadEnter, .goLive), (.space, .next), (.rightArrow, .next),
            (.downArrow, .next), (.leftArrow, .previous), (.upArrow, .previous), (.escape, .clear),
        ]
        for (key, command) in expected {
            #expect(KeyRouting.transportCommand(for: key, textInputFocused: false, sheetOpen: false) == command, "\(key)")
        }
        #expect(KeyRouting.transportCommand(for: .other, textInputFocused: false, sheetOpen: false) == nil)
    }

    @Test func nothingGoesToTheTransportWhileATextInputIsBeingEdited() {
        for key: KeyboardKey in [.returnKey, .keypadEnter, .space, .leftArrow, .rightArrow, .upArrow, .downArrow, .escape, .other] {
            #expect(KeyRouting.decision(for: key, textInputFocused: true, sheetOpen: false) == .passThrough, "\(key)")
        }
    }

    @Test func nothingGoesToTheTransportWhileASheetIsOpen() {
        for key: KeyboardKey in [.returnKey, .space, .leftArrow, .rightArrow, .escape] {
            #expect(KeyRouting.decision(for: key, textInputFocused: false, sheetOpen: true) == .passThrough, "\(key)")
            #expect(KeyRouting.decision(for: key, textInputFocused: true, searchFieldFocused: true, sheetOpen: true) == .passThrough)
        }
    }

    @Test func escapeInTheSearchFieldLeavesItAndOtherKeysStayInTheField() {
        #expect(KeyRouting.decision(for: .escape, textInputFocused: true, searchFieldFocused: true, sheetOpen: false) == .leaveSearch)
        #expect(KeyRouting.decision(for: .space, textInputFocused: true, searchFieldFocused: true, sheetOpen: false) == .passThrough)
        #expect(KeyRouting.decision(for: .returnKey, textInputFocused: true, searchFieldFocused: true, sheetOpen: false) == .passThrough)
        // Escape in another text input (a slide editor) is the field's own business, not "leave search".
        #expect(KeyRouting.decision(for: .escape, textInputFocused: true, searchFieldFocused: false, sheetOpen: false) == .passThrough)
    }

    @Test func menuShortcutsAreNeverTransportKeys() {
        #expect(KeyRouting.decision(for: .returnKey, textInputFocused: false, sheetOpen: false, commandModifierDown: true) == .passThrough)
        #expect(KeyRouting.decision(for: .space, textInputFocused: false, sheetOpen: false, commandModifierDown: true) == .passThrough)
    }

    @Test func keyCodesMapToKeys() {
        #expect(KeyboardKey(keyCode: 36) == .returnKey)
        #expect(KeyboardKey(keyCode: 76) == .keypadEnter)
        #expect(KeyboardKey(keyCode: 49) == .space)
        #expect(KeyboardKey(keyCode: 123) == .leftArrow)
        #expect(KeyboardKey(keyCode: 124) == .rightArrow)
        #expect(KeyboardKey(keyCode: 126) == .upArrow)
        #expect(KeyboardKey(keyCode: 125) == .downArrow)
        #expect(KeyboardKey(keyCode: 53) == .escape)
        #expect(KeyboardKey(keyCode: 0) == .other)
    }
}

// SLIDE-001b: the Delete key removes the selected slide object, but never while something is being typed.
@Suite struct DeleteKeyRoutingTests {
    @Test func virtualKeyCodesForDeleteAreRecognised() {
        #expect(KeyboardKey(keyCode: 51) == .deleteKey && KeyboardKey(keyCode: 117) == .deleteKey)
    }

    @Test func deleteIsForTheSelectedObjectWhenNothingIsBeingTyped() {
        #expect(KeyRouting.decision(for: .deleteKey, textInputFocused: false, sheetOpen: false) == .deleteSelectedObject)
        #expect(KeyRouting.transportCommand(for: .deleteKey, textInputFocused: false, sheetOpen: false) == nil)
    }

    @Test func deleteStaysInATextFieldASheetOrAMenuShortcut() {
        #expect(KeyRouting.decision(for: .deleteKey, textInputFocused: true, sheetOpen: false) == .passThrough)
        #expect(KeyRouting.decision(for: .deleteKey, textInputFocused: true, searchFieldFocused: true, sheetOpen: false) == .passThrough)
        #expect(KeyRouting.decision(for: .deleteKey, textInputFocused: false, sheetOpen: true) == .passThrough)
        #expect(KeyRouting.decision(for: .deleteKey, textInputFocused: false, sheetOpen: false, commandModifierDown: true) == .passThrough)
    }
}
