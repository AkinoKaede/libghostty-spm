import Foundation

extension TerminalViewState {
    public var keywordHighlightRules: [TerminalKeywordHighlightRule] { controller.keywordHighlightRules }

    /// Updates existing surfaces and surfaces created later. Empty rules clear all keyword colors.
    @discardableResult
    public func setKeywordHighlightRules(_ rules: [TerminalKeywordHighlightRule]) -> Bool {
        controller.setKeywordHighlightRules(rules) { self.objectWillChange.send() }
    }
}
