// LIB-004c: pure rules of the scripture interface. How much a slide may hold under a theme, what is offered while a book name is
// typed, how a verse slide becomes a slide on the screens, and how a translation is described in the list. No UI, no storage.
import Foundation
import Domain
import ScriptureEngine
import ScriptureStore

/// How many characters of verse text one slide may hold, from the theme's text boxes (item 3: "the current theme's limits").
///
/// The theme says where the words go and how big they are; this turns that into a character budget for `VerseSlides`. It is an
/// estimate (an average letter is about half as wide as the type is tall, lines are 1.15 times the type size, the canvas is
/// 1920 by 1080), kept a little under the full box, and one line is always left for the reference.
public enum ScriptureSlideLimits {
    static let canvasWidth = 1920.0
    static let canvasHeight = 1080.0
    static let lineHeight = 1.15
    static let letterWidth = 0.48
    static let fill = 0.92
    static let smallest = 20

    public static func options(theme: Theme, bilingual: Bool, versesPerSlide: Int) -> SlideOptions {
        var limit = capacity(of: theme.primary)
        if bilingual, let second = theme.secondary { limit = min(limit, capacity(of: second)) }
        let perSlide = max(versesPerSlide, 1)
        return SlideOptions(versesPerSlide: perSlide, maxCharacters: limit, verseNumbers: perSlide > 1 ? .superscript : .none)
    }

    /// Characters of verse text that fit in the block, after one line for the reference.
    static func capacity(of block: TextBlock) -> Int {
        let size = max(block.style.fontSize, 1)
        let lines = Int((block.frame.height * canvasHeight) / (size * lineHeight))
        let verseLines = max(lines - 1, 1)
        let perLine = max(Int((block.frame.width * canvasWidth) / (size * letterWidth)), 1)
        return max(Int(Double(verseLines * perLine) * fill), smallest)
    }
}

/// A book offered while the operator types a reference.
public struct ScriptureSuggestion: Equatable, Sendable, Identifiable {
    public var book: BookID
    /// The book's name in the language it was matched in ("John", "Giăng").
    public var name: String
    public var language: ScriptureLanguage
    public var id: String { "\(book.rawValue)-\(language.rawValue)" }
    /// What the field becomes when this is chosen: the name and a space, ready for the chapter.
    public var completion: String { name + " " }
}

public enum ScriptureSuggestions {
    public static let limit = 8

    /// Books whose English or Vietnamese name starts with what was typed (case, accents, spaces and hyphens do not matter), in canon
    /// order. Nothing once the typed text goes past the book name into numbers, and nothing for an empty field.
    public static func suggest(_ text: String) -> [ScriptureSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // A leading book number ("1 jo") is part of the name; any other digit means the chapter has started.
        let chars = Array(trimmed)
        var i = 0
        while i < chars.count, chars[i].isASCII, chars[i].isNumber { i += 1 }
        let rest = String(chars[i...])
        guard !rest.contains(where: { $0.isASCII && $0.isNumber }) else { return [] }
        let key = squash(trimmed)
        guard !key.isEmpty else { return [] }

        var out: [ScriptureSuggestion] = []
        for book in Canon.books {
            for language in ScriptureLanguage.allCases {
                guard let name = BookNames.displayName(book.id, language), squash(name).hasPrefix(key) else { continue }
                out.append(ScriptureSuggestion(book: book.id, name: name, language: language))
                break
            }
        }
        return Array(out.prefix(limit))
    }

    private static func squash(_ text: String) -> String {
        SearchFolding.fold(text).filter { !$0.isWhitespace }
    }
}

/// A verse slide as the screens get it: its words with the reference as the last line of each side. The reference is part of the
/// words so that it reaches every screen: a transparent broadcast screen draws the lower-third words but leaves slide objects out.
public enum ScriptureSlideContent {
    public static func content(for slide: ScriptureSlide) -> SlideContent {
        let primary = slide.content.primary + "\n" + slide.reference
        var secondary: String?
        if let text = slide.content.secondary {
            secondary = slide.secondaryReference.map { text + "\n" + $0 } ?? text
        }
        return SlideContent(primary: primary, secondary: secondary)
    }
}

/// How a stored translation reads in the Translations list.
public enum TranslationRow {
    public static func copyrightLine(_ translation: StoredTranslation) -> String {
        let line = translation.copyright?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return line.isEmpty ? "No copyright line came with this file." : line
    }

    public static func languageName(_ tag: String) -> String {
        let code = String(tag.split(separator: "-").first ?? "").lowercased()
        if let name = Locale(identifier: "en").localizedString(forLanguageCode: code), !name.isEmpty { return name.capitalized }
        return tag
    }
}
