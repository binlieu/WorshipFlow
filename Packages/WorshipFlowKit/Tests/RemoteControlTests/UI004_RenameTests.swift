// UI-004: the phone page says WorshipFlow.
import Testing
@testable import RemoteControl

@Suite struct UI004_RemoteNameTests {
    @Test func theRemotePageUsesTheNewSpelling() {
        #expect(ControlPage.html.contains("WorshipFlow remote"))
        #expect(!ControlPage.html.contains("WORSHIPFLOW"))
    }
}
