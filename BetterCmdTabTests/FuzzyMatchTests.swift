import Testing
@testable import BetterCmdTab

@Suite("FuzzyMatch")
struct FuzzyMatchTests {

    @Test("empty query matches everything")
    func emptyQuery() {
        #expect(FuzzyMatch.matches(query: "", appName: "Safari", windowTitle: "Apple"))
        #expect(FuzzyMatch.matches(query: "   ", appName: "Safari", windowTitle: ""))
    }

    @Test("subsequence matches against app name")
    func appNameSubsequence() {
        #expect(FuzzyMatch.matches(query: "gh", appName: "GitHub", windowTitle: ""))
        #expect(FuzzyMatch.matches(query: "sfri", appName: "Safari", windowTitle: ""))
    }

    @Test("matches against window title when app name does not match")
    func windowTitleSubsequence() {
        #expect(FuzzyMatch.matches(query: "invoice", appName: "Preview", windowTitle: "Invoice 2026.pdf"))
        #expect(!FuzzyMatch.matches(query: "invoice", appName: "Preview", windowTitle: "Receipt.pdf"))
    }

    @Test("case and diacritics are ignored")
    func caseAndDiacritics() {
        #expect(FuzzyMatch.matches(query: "CAFE", appName: "Café", windowTitle: ""))
        #expect(FuzzyMatch.matches(query: "café", appName: "cafe bar", windowTitle: ""))
    }

    @Test("whitespace in the query is ignored")
    func whitespaceIgnored() {
        #expect(FuzzyMatch.matches(query: "git hub", appName: "GitHub", windowTitle: ""))
    }

    @Test("non-subsequence does not match")
    func noMatch() {
        #expect(!FuzzyMatch.matches(query: "xyz", appName: "Safari", windowTitle: "Terminal"))
        // Out-of-order characters are not a subsequence.
        #expect(!FuzzyMatch.matches(query: "bha", appName: "Safari", windowTitle: ""))
    }
}
