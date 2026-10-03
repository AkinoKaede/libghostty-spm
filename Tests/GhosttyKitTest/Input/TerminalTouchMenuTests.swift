#if canImport(UIKit)
    import Testing
    import UIKit

    @testable import GhosttyTerminal

    @Suite @MainActor
    struct TerminalTouchMenuTests {
        @Test(arguments: [false, true])
        func hostCanReorderSystemMenusWithoutADuplicateAppend(selecting: Bool) throws {
            guard #available(iOS 17.0, *) else { return }
            let view = ReorderingTerminalView(frame: .zero)
            view.touchSelection.text = selecting ? "selected terminal text" : nil
            let autoFill = UIMenu(title: "System AutoFill", identifier: .autoFill, children: [])
            let suggested = UIMenu(children: [autoFill])
            let menu = view.touchSelectionMenu(at: .zero, suggestedActions: [suggested])
            let first = try #require(menu.children.first as? UIMenu)
            #expect(first.identifier == .autoFill)
            #expect(first.title == autoFill.title)
            #expect(menu.children.compactMap { $0 as? UIMenu }.filter { $0.identifier == .autoFill }.count == 1)
            let actions = menu.children.compactMap { $0 as? UIAction }.map(\.identifier.rawValue)
            #expect(actions.contains(selecting ? "terminal.copy" : "terminal.select"))
            #expect(actions.contains("terminal.selectAll"))
        }

        @Test(arguments: [false, true])
        func absentSystemMenusLeaveTheTerminalActionsAvailable(selecting: Bool) {
            let view = UITerminalView(frame: .zero)
            view.touchSelection.text = selecting ? "selected terminal text" : nil
            let menu = view.touchSelectionMenu(at: .zero, suggestedActions: [])
            #expect(menu.children.allSatisfy { $0 is UIAction })
            let actions = menu.children.compactMap { $0 as? UIAction }.map(\.identifier.rawValue)
            #expect(actions.contains(selecting ? "terminal.copy" : "terminal.select"))
            #expect(actions.contains("terminal.selectAll"))
        }
    }

    private final class ReorderingTerminalView: UITerminalView {
        override func touchMenuItems(for context: TerminalTouchMenuContext) -> [UIMenuElement] {
            reorder(super.touchMenuItems(for: context))
        }

        override func touchSelectionMenuItems(for context: TerminalTouchSelectionMenuContext) -> [UIMenuElement] {
            reorder(super.touchSelectionMenuItems(for: context))
        }

        private func reorder(_ items: [UIMenuElement]) -> [UIMenuElement] {
            items.filter { $0 is UIMenu } + items.filter { !($0 is UIMenu) }
        }
    }
#endif
