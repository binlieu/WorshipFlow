// LIB-004: split a long verse across slides at sentence or clause boundaries, never in the middle of a word.
// Works on whitespace-separated words, which is all Vietnamese needs (its syllables are written as words).
import Foundation

enum TextSplitter {
    private enum Strength { case strong, weak, none }

    private static let sentenceEnd: Set<Character> = [".", "!", "?", "\u{2026}", "\u{3002}"]
    private static let clauseEnd: Set<Character> = [",", ";", ":", "\u{2014}", "\u{2013}", "\u{2012}"]
    private static let closers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", ")", "]", "\u{00BB}", "}"]

    private static func strength(of word: String) -> Strength {
        var chars = Array(word)
        while let last = chars.last, closers.contains(last) { chars.removeLast() }
        guard let last = chars.last else { return .none }
        if sentenceEnd.contains(last) { return .strong }
        if clauseEnd.contains(last) { return .weak }
        return .none
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Parts no longer than `maxCharacters` where possible, balanced, preferring sentence ends, then clause ends,
    /// then any space. A single word longer than the limit stays whole. A limit of 0 or less means no limit.
    static func split(_ text: String, maxCharacters: Int) -> [String] {
        let w = words(text)
        guard !w.isEmpty else { return [] }
        if maxCharacters <= 0 { return [w.joined(separator: " ")] }
        let strengths = w.map(strength(of:))
        // prefix[k] = length of words[0..<k] joined with single spaces.
        var prefix = [0]
        for (i, word) in w.enumerated() { prefix.append(prefix[i] + word.count + (i > 0 ? 1 : 0)) }
        func length(_ from: Int, _ to: Int) -> Int { // words from..<to
            prefix[to] - prefix[from] - (from > 0 ? 1 : 0)
        }

        // Fewest parts first: a greedy fill gives the minimum count. A word longer than the limit is a part by itself.
        var count = 0
        var at = 0
        while at < w.count {
            var end = at + 1
            while end < w.count, length(at, end + 1) <= maxCharacters { end += 1 }
            count += 1
            at = end
        }
        if count == 1 { return [w.joined(separator: " ")] }

        // Then, among all ways to cut into exactly that many parts that respect the limit, pick the one whose
        // parts are closest to equal length and whose cuts fall on sentence ends, then clause ends.
        let target = Double(length(0, w.count)) / Double(count)
        func cutPenalty(_ lastWord: Int) -> Double {
            (strengths[lastWord] == .strong ? 0 : (strengths[lastWord] == .weak ? 0.15 : 0.5)) * target
        }
        let n = w.count
        let inf = Double.infinity
        // cost[p][i]: best cost to cover words[i..<n] with p parts; choice[p][i]: where the first part ends.
        var cost = Array(repeating: Array(repeating: inf, count: n + 1), count: count + 1)
        var choice = Array(repeating: Array(repeating: -1, count: n + 1), count: count + 1)
        cost[0][n] = 0
        if count >= 1 {
            for p in 1...count {
                for i in 0..<n {
                    var j = i + 1
                    while j <= n {
                        let len = length(i, j)
                        if len > maxCharacters, j > i + 1 { break }
                        let rest = cost[p - 1][j]
                        if rest < inf {
                            let isLast = p == 1
                            let c = abs(Double(len) - target) + (isLast ? 0 : cutPenalty(j - 1)) + rest
                            if c < cost[p][i] { cost[p][i] = c; choice[p][i] = j }
                        }
                        j += 1
                    }
                }
            }
        }
        var parts: [String] = []
        var i = 0
        var p = count
        while i < n, p > 0, choice[p][i] > i {
            let j = choice[p][i]
            parts.append(w[i..<j].joined(separator: " "))
            i = j
            p -= 1
        }
        if i < n { parts.append(w[i...].joined(separator: " ")) }
        return parts
    }

    /// Exactly `count` parts (padded with empty strings when there are fewer words than parts), cut near equal
    /// lengths, preferring sentence and clause ends.
    static func split(_ text: String, into count: Int) -> [String] {
        let w = words(text)
        let n = max(count, 1)
        if n == 1 { return [w.joined(separator: " ")] }
        var parts: [String] = []
        var start = 0
        let strengths = w.map(strength(of:))
        for index in 0..<n {
            let partsLeft = n - index
            if start >= w.count { parts.append(""); continue }
            if partsLeft == 1 { parts.append(w[start...].joined(separator: " ")); start = w.count; continue }
            let remaining = w[start...].joined(separator: " ").count
            let target = Double(remaining) / Double(partsLeft)
            // Leave at least one word for each later part when there are enough words.
            let lastCut = max(start, w.count - partsLeft)
            var best = start
            var bestScore = Double.infinity
            var len = 0
            for k in start...lastCut {
                len += w[k].count + (k > start ? 1 : 0)
                let penalty: Double = strengths[k] == .strong ? 0 : (strengths[k] == .weak ? 0.15 : 0.5)
                let score = abs(Double(len) - target) + penalty * target
                if score < bestScore { bestScore = score; best = k }
            }
            parts.append(w[start...best].joined(separator: " "))
            start = best + 1
        }
        return parts
    }
}
