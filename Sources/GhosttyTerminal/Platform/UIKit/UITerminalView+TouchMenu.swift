//
//  UITerminalView+TouchMenu.swift
//  libghostty-spm
//

#if canImport(UIKit)
    import UIKit

    extension UITerminalView {
        var isTouchMenuVisible: Bool {
            if #available(iOS 16.0, *) {
                return touchSelection.menuVisible
            }
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
                        identifier: "terminal.touchMenu" as NSString,
                        sourcePoint: point
                    )
                )
            } else {
                UIMenuController.shared.showMenu(
                    from: self,
                    rect: CGRect(origin: point, size: CGSize(width: 1, height: 1))
                )
            }
        }

        func touchSelectionMenu(at point: CGPoint, suggestedActions: [UIMenuElement]) -> UIMenu {
            let items: [UIMenuElement]
            if let text = touchSelection.text {
                items = touchSelectionMenuItems(
                    for: TerminalTouchSelectionMenuContext(sourcePoint: point, selectedText: text)
                )
            } else {
                items = touchMenuItems(for: TerminalTouchMenuContext(sourcePoint: point))
            }
            // UIKit owns compact presentation, overflow arrows and expansion.
            return UIMenu(children: items + systemAutoFillMenus(in: suggestedActions))
        }

        private func systemAutoFillMenus(in elements: [UIMenuElement]) -> [UIMenuElement] {
            guard #available(iOS 17.0, *) else { return [] }
            return elements.flatMap { element -> [UIMenuElement] in
                guard let menu = element as? UIMenu else { return [] }
                if menu.identifier == .autoFill {
                    return [menu]
                }
                return systemAutoFillMenus(in: menu.children)
            }
        }

        func presentTouchSelectionMenu(at point: CGPoint) {
            guard touchSelection.range != nil else { return }
            if #available(iOS 16.0, *) {
                selectionEditMenuInteraction.presentEditMenu(
                    with: UIEditMenuConfiguration(
                        identifier: "terminal.touchSelection" as NSString,
                        sourcePoint: CGPoint(
                            x: min(bounds.maxX, max(0, point.x)),
                            y: min(bounds.maxY, max(0, point.y))
                        )
                    )
                )
            } else {
                showSelectionCopyMenu(at: point)
            }
        }
    }

    @available(iOS 16.0, *)
    extension UITerminalView: @preconcurrency UIEditMenuInteractionDelegate {
        public func editMenuInteraction(
            _: UIEditMenuInteraction,
            willPresentMenuFor _: UIEditMenuConfiguration,
            animator _: any UIEditMenuInteractionAnimating
        ) {
            touchSelection.menuVisible = true
        }

        public func editMenuInteraction(
            _: UIEditMenuInteraction,
            willDismissMenuFor _: UIEditMenuConfiguration,
            animator: any UIEditMenuInteractionAnimating
        ) {
            touchSelection.menuVisible = false
            guard let action = touchSelection.pendingAction else { return }
            touchSelection.pendingAction = nil
            animator.addCompletion(action)
        }

        public func editMenuInteraction(
            _: UIEditMenuInteraction,
            menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            if configuration.identifier as? String == "terminal.touchMenu"
                || configuration.identifier as? String == "terminal.touchSelection"
            {
                return touchSelectionMenu(at: configuration.sourcePoint, suggestedActions: suggestedActions)
            }
            return UIMenu(children: suggestedActions)
        }
    }
#endif
