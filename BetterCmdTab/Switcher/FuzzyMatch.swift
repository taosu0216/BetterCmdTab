import Foundation

enum FuzzyMatch {
    /// True when every character of `query` appears, in order but not
    /// necessarily contiguous, within `appName` OR `windowTitle`. Case- and
    /// diacritic-insensitive; whitespace in the query is ignored so "git hub"
    /// still matches "GitHub". An empty query matches everything.
    static func matches(query: String, appName: String, windowTitle: String) -> Bool {
        let q = fold(query).filter { !$0.isWhitespace }
        guard !q.isEmpty else { return true }
        return isSubsequence(q, of: fold(appName)) || isSubsequence(q, of: fold(windowTitle))
    }

    static func fold(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: nil).lowercased()
    }

    /// Whether `needle`'s characters appear in order within `haystack`.
    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var iterator = needle.makeIterator()
        var current = iterator.next()
        for ch in haystack where ch == current {
            current = iterator.next()
            if current == nil { return true }
        }
        return current == nil
    }
}
