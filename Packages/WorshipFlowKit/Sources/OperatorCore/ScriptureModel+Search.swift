// LIB-004c item 6: searching verse text. The words are folded (case, accents, đ and punctuation do not matter), so a Vietnamese
// word typed without its accents finds the verse. Results carry their reference; choosing one opens its passage.
import Foundation
import Domain
import ScriptureEngine
import ScriptureStore

extension ScriptureModel {
    static let searchLimit = 50

    /// Searches the first translation. An empty query clears the results.
    public func search(_ text: String) async {
        searchText = text
        searchToken += 1
        let token = searchToken
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []; searchTruncated = false; searchMessage = nil
            return
        }
        guard let code = primaryCode else {
            searchResults = []; searchTruncated = false
            searchMessage = "No translation is installed to search. Import one first (Translations, then Import)."
            return
        }
        do {
            let found = try await store.search(query, translationCode: code, limit: Self.searchLimit)
            let table = try await store.versification(for: code)
            guard token == searchToken else { return }
            let language = ScriptureLanguage(languageTag: translation(code)?.language ?? "en")
            searchResults = found.hits.map { hit in
                ScriptureSearchRow(ref: hit.ref,
                                   reference: ReferenceFormatter.format(VerseRange(hit.ref), language: language, versification: table),
                                   snippet: hit.snippet)
            }
            searchTruncated = found.truncated
            searchMessage = searchResults.isEmpty ? "Nothing found. Searching ignores accents and capital letters." : nil
        } catch {
            guard token == searchToken else { return }
            searchResults = []; searchTruncated = false
            searchMessage = Self.message(for: error)
        }
    }

    /// Opens the passage of a result (the verse itself; the operator can type a longer reference to take more).
    public func openSearchResult(_ row: ScriptureSearchRow) async {
        await show(row.reference)
    }
}
