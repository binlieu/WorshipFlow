// FIX-B R4: may the app quit, close its operator window or hide now, and what must it ask first?
import Testing
@testable import OperatorCore

@Suite struct QuitPolicyTests {
    @Test func quittingWithNoScreensOpenJustQuits() {
        #expect(QuitPolicy.decision(for: .quitCommand, screensOpen: false) == .allow)
        #expect(QuitPolicy.decision(for: .lastWindowClosed, screensOpen: false) == .allow)
        #expect(QuitPolicy.decision(for: .operatorWindowClose, screensOpen: false) == .allow)
    }

    @Test func quittingWhileScreensAreOpenAsksFirstAndSaysWhatWillHappen() {
        guard case .confirm(let title, let message, let confirmTitle) = QuitPolicy.decision(for: .quitCommand, screensOpen: true) else {
            Issue.record("expected a confirmation")
            return
        }
        #expect(title.contains("Quit"))
        #expect(message.contains("screens"))
        #expect(confirmTitle.contains("Quit"))
    }

    @Test func closingTheOperatorWindowWhileScreensAreOpenIsRefusedWithAMessage() {
        guard case .refuse(let message) = QuitPolicy.decision(for: .operatorWindowClose, screensOpen: true) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(message.contains("screens"))
    }

    @Test func theAppNeverQuitsBecauseTheLastWindowClosedWhileScreensAreOpen() {
        if case .refuse = QuitPolicy.decision(for: .lastWindowClosed, screensOpen: true) {} else {
            Issue.record("expected a refusal")
        }
    }

    @Test func hidingTheAppIsOnlyAllowedWhenNoScreenIsOpen() {
        #expect(QuitPolicy.mayHide(screensOpen: false))
        #expect(!QuitPolicy.mayHide(screensOpen: true))
    }
}
