import Testing

@testable import GhosttyTerminal

@MainActor
struct TerminalKeywordHighlightTests {
    @Test func literalSyntaxAndNewlinesCannotInjectConfiguration() {
        let rule = TerminalKeywordHighlightRule(pattern: "[error].*\\E\nfont-size = 80", foregroundRGB: 0x123ABC)
        #expect(rule.validationIssue() == nil)
        #expect(rule.configurationValue.contains(#"\[error\]\.\*\\E\nfont-size = 80"#))
        #expect(!rule.configurationValue.contains("\n"))
    }

    @Test func anExplicitEmptyOverrideClearsRulesFromTheBaseConfig() {
        let state = TerminalViewState(configSource: .generated("keyword-highlight = FF0000,-:Warn\n"))
        #expect(state.setKeywordHighlightRules([]))
        #expect(state.renderedConfig.hasSuffix("keyword-highlight = \n"))
        state.setTerminalConfiguration(.init { $0.withFontSize(19) })
        #expect(state.renderedConfig.hasSuffix("keyword-highlight = \n"))
    }

    @Test func optionalForegroundAndBackgroundColorsRenderIndependently() {
        let rule = TerminalKeywordHighlightRule(pattern: "Warn", backgroundRGB: 0x123456)
        #expect(rule.validationIssue() == nil)
        #expect(rule.configurationValue == "-,123456:(?i:Warn)")
        #expect(TerminalKeywordHighlightRule(pattern: "x").configurationValue == "-,-:(?i:x)")
        #expect(TerminalKeywordHighlightRule(pattern: "x", backgroundRGB: 0x1000000).validationIssue() != nil)
        let state = TerminalViewState(configSource: .none)
        #expect(state.setKeywordHighlightRules([rule]))
        #expect(state.keywordHighlightRules.first?.foregroundRGB == nil)
        #expect(state.keywordHighlightRules.first?.backgroundRGB == 0x123456)
    }

    @Test func invalidUpdatesPreserveThePreviousRules() {
        let state = TerminalViewState(configSource: .none)
        let good = TerminalKeywordHighlightRule(pattern: "Warn", foregroundRGB: 0x123456)
        #expect(state.setKeywordHighlightRules([good]))
        for bad in [
            TerminalKeywordHighlightRule(pattern: "[", mode: .regularExpression, foregroundRGB: 0),
            TerminalKeywordHighlightRule(pattern: "x", foregroundRGB: 0x1000000),
            TerminalKeywordHighlightRule(pattern: "\0", foregroundRGB: 0),
            TerminalKeywordHighlightRule(pattern: "", foregroundRGB: 0),
        ] {
            #expect(bad.validationIssue() != nil)
            #expect(!state.setKeywordHighlightRules([bad]))
            #expect(state.keywordHighlightRules == [good])
        }
        #expect(!state.setKeywordHighlightRules(Array(repeating: good, count: 65)))
        #expect(state.keywordHighlightRules == [good])
        #expect(state.setKeywordHighlightRules([]))
        #expect(state.keywordHighlightRules.isEmpty)
        #expect(!state.renderedConfig.contains("123456,-:"))
    }

    @Test func orderCaseSensitivityAndThemeReconfigurationArePreserved() {
        let first = TerminalKeywordHighlightRule(pattern: "Warn", isCaseSensitive: true, foregroundRGB: 0xFF0000)
        let second = TerminalKeywordHighlightRule(pattern: "warn", foregroundRGB: 0x00FF00)
        let state = TerminalViewState(configSource: .none)
        #expect(state.setKeywordHighlightRules([first, second]))
        state.setTerminalConfiguration(.init { $0.withFontSize(19) })
        #expect(state.keywordHighlightRules == [first, second])
        #expect(
            state.renderedConfig.contains("keyword-highlight = FF0000,-:Warn\nkeyword-highlight = 00FF00,-:(?i:warn)"))
        #expect(state.renderedConfig.contains("font-size = 19"))
    }
}
