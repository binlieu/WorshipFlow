// UI-004: renaming the product to WorshipFlow must not move an existing library. The folder under Application Support keeps
// the spelling the first builds used, whatever the app is called now.
import Testing
import Foundation
@testable import Persistence

@Suite struct UI004_LibraryLocationTests {
    @Test func theDefaultLibraryStaysWhereEarlierBuildsPutIt() {
        let base = URL(fileURLWithPath: "/Users/someone/Library/Application Support", isDirectory: true)
        #expect(LibraryLocation.defaultURL(applicationSupport: base).path == "/Users/someone/Library/Application Support/WORSHIPFLOW/Library.sqlite")
    }

    @Test func theFolderNameIsNotDerivedFromTheBundleName() {
        #expect(LibraryLocation.folderName == "WORSHIPFLOW")
        #expect(LibraryLocation.fileName == "Library.sqlite")
    }
}
