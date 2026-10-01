//
//  TerminalTouchSelectionMenuContext.swift
//  libghostty-spm
//

#if canImport(UIKit)
    import UIKit

    /// Context for the terminal menu while text is selected.
    public struct TerminalTouchSelectionMenuContext {
        /// Location in the terminal view's coordinate space.
        public let sourcePoint: CGPoint
        /// A snapshot of the selected terminal text when the menu is built.
        public let selectedText: String
    }
#endif
