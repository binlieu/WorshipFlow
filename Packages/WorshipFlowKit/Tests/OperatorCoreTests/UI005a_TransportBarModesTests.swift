// UI-005a: the transport bar is hidden in Edit, Stage and Screens, and the keyboard keeps working in every mode.
import Testing
@testable import OperatorCore

@Suite struct UI005a_TransportBarModesTests {
    @Test func theBarIsDrawnInShowMediaAndCuesOnly() {
        #expect(WorkspaceMode.allCases.filter(\.showsTransportBar) == [.show, .media, .cues])
        #expect(WorkspaceMode.allCases.filter { !$0.showsTransportBar } == [.edit, .stage, .screens])
    }

    @Test func everyTransportKeyDecidesTheSameWhateverTheMode() {
        // The decision has no mode input at all; this pins the answers the three bar-less modes rely on.
        let expected: [(KeyboardKey, TransportCommand)] = [(.returnKey, .goLive), (.space, .next), (.rightArrow, .next), (.leftArrow, .previous), (.escape, .clear), (.b, .blackout)]
        for mode in WorkspaceMode.allCases {
            for (key, command) in expected {
                let decision = KeyRouting.decision(for: key, textInputFocused: false, sheetOpen: false)
                #expect(decision == .transport(command), "\(key) in \(mode.title)")
            }
            #expect(KeyRouting.decision(for: .escape, textInputFocused: false, sheetOpen: false, shiftDown: true) == .transport(.clearAll))
        }
    }
}
