// UI-005b: the language of a field's words, named in that language ("English", "Tiếng Việt"), for the Quick edit labels. The
// library stores no language, so this reads the words themselves; when it cannot tell it returns nil and the label stays
// "First language". Nothing here is stored: it is a reading of the words, drawn as a label, never as a setting.
import Foundation
import NaturalLanguage

public enum LanguageNaming {
    /// Needed before a guess is made: fewer letters than this say too little.
    static let minimumLetters = 12
    static let minimumConfidence = 0.6

    /// What the words seem to be in: the language code and its name in that language.
    struct Detected: Equatable { var code: String; var ownName: String }

    public static func name(of texts: [String]) -> String? { detect(texts)?.ownName }

    /// FIX-H item 13: a reading of the words is a guess, so it is offered as a question ("Vietnamese?") in the operator's own language,
    /// never stated as a fact. Nil when the words do not say.
    public static func suggestion(of texts: [String], in locale: Locale = .current) -> String? {
        guard let detected = detect(texts) else { return nil }
        return suggestion(for: detected, in: locale)
    }

    static func suggestion(for detected: Detected, in locale: Locale) -> String {
        let name = locale.localizedString(forLanguageCode: detected.code).flatMap { $0.isEmpty ? nil : $0 } ?? detected.ownName
        return name.prefix(1).uppercased() + name.dropFirst() + "?"
    }

    static func detect(_ texts: [String]) -> Detected? {
        let joined = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard joined.filter(\.isLetter).count >= minimumLetters else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(joined.prefix(2000)))
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minimumConfidence, language != .undetermined else { return nil }
        let own = Locale(identifier: language.rawValue)
        guard let name = own.localizedString(forLanguageCode: language.rawValue), !name.isEmpty else { return nil }
        return Detected(code: language.rawValue, ownName: name.prefix(1).uppercased() + name.dropFirst())
    }
}
