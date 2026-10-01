#if canImport(UIKit)
    import UIKit

    /// Context for app actions shown before text is selected.
    public struct TerminalTouchMenuContext {
        /// Location in the terminal view's coordinate space.
        public let sourcePoint: CGPoint
    }

    /// Context for app actions shown while terminal text is selected.
    public struct TerminalTouchSelectionMenuContext {
        public let sourcePoint: CGPoint
        /// A snapshot of the selected terminal text when the menu is built.
        public let selectedText: String
    }

    extension UITerminalView {
        var isTouchMenuVisible: Bool {
            if #available(iOS 16.0, *) { return touchSelection.menuVisible }
            return UIMenuController.shared.isMenuVisible
        }

        func presentTouchMenu(at point: CGPoint) {
            guard surface != nil else { return }
            stopMomentumScrolling()
            becomeFirstResponder()
            touchSelection.menuPoint = point
            if #available(iOS 16.0, *) {
                selectionEditMenuInteraction.presentEditMenu(
                    with: UIEditMenuConfiguration(
                        identifier: "terminal.touchMenu" as NSString, sourcePoint: point
                    ))
            } else {
                UIMenuController.shared.showMenu(
                    from: self, rect: CGRect(origin: point, size: CGSize(width: 1, height: 1)))
            }
        }

        func touchSelectionMenu(at point: CGPoint, selecting: Bool, suggestedActions: [UIMenuElement]) -> UIMenu {
            let primary = UIMenu(
                identifier: .standardEdit, options: .displayInline,
                children: touchPrimaryActions(at: point, selecting: selecting))
            if #available(iOS 16.0, *) { primary.preferredElementSize = .medium }
            let additional: [UIMenuElement]
            if selecting, let text = touchSelection.text {
                additional = touchSelectionMenuItems(
                    for: TerminalTouchSelectionMenuContext(sourcePoint: point, selectedText: text))
            } else {
                additional = touchMenuItems(for: TerminalTouchMenuContext(sourcePoint: point))
            }
            // UIKit owns compact presentation, overflow arrows and expansion.
            return UIMenu(children: [primary] + systemAutoFillMenus(in: suggestedActions) + additional)
        }

        private func touchPrimaryActions(at point: CGPoint, selecting: Bool) -> [UIMenuElement] {
            let titles = touchSelection.titles
            let paste = UIAction(title: titles.paste, image: UIImage(systemName: "document.on.clipboard")) {
                [weak self] _ in
                self?.dismissTouchSelection()
                self?.pasteFromPasteboard()
            }
            let select = UIAction(title: titles.select, image: UIImage(systemName: "selection.pin.in.out")) {
                [weak self] _ in
                self?.touchSelection.pendingAction = { [weak self] in
                    self?.beginTouchSelection(at: point, selectAll: false)
                }
            }
            let all = UIAction(title: titles.selectAll, image: UIImage(systemName: "character.textbox")) {
                [weak self] _ in
                self?.touchSelection.pendingAction = { [weak self] in
                    self?.beginTouchSelection(at: point, selectAll: true)
                }
            }
            let copy = UIAction(title: titles.copy, image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                _ = self?.copyTouchSelection()
            }
            let pasteActions: [UIMenuElement] = TerminalPasteboardContent.hasContent() ? [paste] : []
            return selecting ? [copy] + pasteActions + [all] : pasteActions + [select, all]
        }

        private func systemAutoFillMenus(in elements: [UIMenuElement]) -> [UIMenuElement] {
            guard #available(iOS 17.0, *) else { return [] }
            return elements.flatMap { element -> [UIMenuElement] in
                guard let menu = element as? UIMenu else { return [] }
                if menu.identifier == .autoFill { return [menu] }
                return systemAutoFillMenus(in: menu.children)
            }
        }

        func presentTouchSelectionMenu(at point: CGPoint) {
            guard touchSelection.range != nil else { return }
            if #available(iOS 16.0, *) {
                selectionEditMenuInteraction.presentEditMenu(
                    with: UIEditMenuConfiguration(
                        identifier: "terminal.touchSelection" as NSString,
                        sourcePoint: CGPoint(x: min(bounds.maxX, max(0, point.x)), y: min(bounds.maxY, max(0, point.y)))
                    ))
            } else {
                showSelectionCopyMenu(at: point)
            }
        }
    }

    @available(iOS 16.0, *)
    extension UITerminalView: @preconcurrency UIEditMenuInteractionDelegate {
        public func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            willPresentMenuFor configuration: UIEditMenuConfiguration,
            animator: any UIEditMenuInteractionAnimating
        ) {
            touchSelection.menuVisible = true
        }

        public func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            willDismissMenuFor configuration: UIEditMenuConfiguration,
            animator: any UIEditMenuInteractionAnimating
        ) {
            touchSelection.menuVisible = false
            guard let action = touchSelection.pendingAction else { return }
            touchSelection.pendingAction = nil
            animator.addCompletion(action)
        }

        public func editMenuInteraction(
            _ interaction: UIEditMenuInteraction,
            menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            if configuration.identifier as? String == "terminal.touchMenu"
                || configuration.identifier as? String == "terminal.touchSelection"
            {
                return touchSelectionMenu(
                    at: configuration.sourcePoint, selecting: touchSelection.range != nil,
                    suggestedActions: suggestedActions)
            }
            return UIMenu(children: suggestedActions)
        }
    }
#endif
