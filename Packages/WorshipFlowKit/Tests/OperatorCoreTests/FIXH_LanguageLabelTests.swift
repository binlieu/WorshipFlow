// FIX-H item 13 (UI-005b): the Quick edit field labels. The library stores no language for a presentation or a slide (the model keeps
// primary and secondary text only), so a language name can only come from reading the words. That reading is a guess, so it is shown
// as a suggestion ("Vietnamese?"), never as a fact, and it is computed when the words change, not on every redraw.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXH_LanguageLabelTests {
    static let en = "Verse 1\nAmazing grace, how sweet the sound\nThat saved a wretch like me\n\nChorus\nMy chains are gone\nI have been set free"
    static let vi = "Câu 1\nÂn điển lạ lùng thay\nĐã cứu vớt tôi\n\nĐiệp khúc\nXiềng xích đã tan\nTôi được tự do"

    private func openedSong(secondary: String?) async throws -> WorkspaceModel {
        let model = WorkspaceModel(store: try LibraryStore.inMemory())
        await model.load()
        model.languageDisplayLocale = Locale(identifier: "en_US")
        let song = try #require(await model.importLyrics(title: "Grace", primaryText: Self.en, secondaryText: secondary, maxLines: 2))
        await model.openPresentation(song.id)
        return model
    }

    @Test func aDetectedNameIsASuggestionWithAQuestionMark() async throws {
        let model = try await openedSong(secondary: Self.vi)
        let labels = model.quickEditLanguageLabels
        #expect(labels.first == QuickEditLanguageLabel(text: "English?", isSuggestion: true))
        #expect(labels.second == QuickEditLanguageLabel(text: "Vietnamese?", isSuggestion: true))
    }

    @Test func whenTheWordsDoNotSayTheLabelIsTheNeutralNameAndNotASuggestion() async throws {
        let model = try await openedSong(secondary: nil)
        #expect(model.quickEditLanguageLabels.second == QuickEditLanguageLabel(text: "Second language", isSuggestion: false))
        let short = WorkspaceModel(store: try LibraryStore.inMemory())
        await short.load()
        #expect(short.quickEditLanguageLabels.first == QuickEditLanguageLabel(text: "First language", isSuggestion: false))
    }

    @Test func theSuggestionIsFoundWhenTheWordsChangeAndNotOnEveryRead() async throws {
        let model = try await openedSong(secondary: Self.vi)
        _ = model.quickEditLanguageLabels
        let afterFirst = model.languageDetections
        #expect(afterFirst > 0)
        for _ in 0..<50 { _ = model.quickEditLanguageLabels }          // redraws
        #expect(model.languageDetections == afterFirst)
        model.editSlide(id: model.slides[0].id, content: SlideContent(primary: "Hallelujah, praise the Lord forever and ever amen", secondary: model.slides[0].content.secondary))
        _ = model.quickEditLanguageLabels
        #expect(model.languageDetections > afterFirst)                  // the words changed: read again
    }

    @Test func theNameOfTheSuggestionFollowsTheOperatorsLanguage() {
        #expect(LanguageNaming.suggestion(of: [Self.vi], in: Locale(identifier: "en_US")) == "Vietnamese?")
        #expect(LanguageNaming.suggestion(of: ["ok"], in: Locale(identifier: "en_US")) == nil)
    }
}
