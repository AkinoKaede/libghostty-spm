//
//  UITerminalView+TouchMenuActions.swift
//  libghostty-spm
//

#if canImport(UIKit)
    import UIKit

    extension UITerminalView {
        func defaultTouchMenuItems(at point: CGPoint, selecting: Bool) -> [UIMenuElement] {
            let paste = UIAction(
                title: "Paste",
                image: UIImage(systemName: "doc.on.clipboard"),
                identifier: UIAction.Identifier("terminal.paste")
            ) { [weak self] _ in
                self?.dismissTouchSelection()
                self?.pasteFromPasteboard()
            }
            let select = UIAction(
                title: "Select",
                image: UIImage(systemName: "selection.pin.in.out"),
                identifier: UIAction.Identifier("terminal.select")
            ) { [weak self] _ in
                self?.touchSelection.pendingAction = { [weak self] in
                    self?.beginTouchSelection(at: point, selectAll: false)
                }
            }
            let selectAll = UIAction(
                title: "Select All",
                image: UIImage(systemName: "character.textbox"),
                identifier: UIAction.Identifier("terminal.selectAll")
            ) { [weak self] _ in
                self?.touchSelection.pendingAction = { [weak self] in
                    self?.beginTouchSelection(at: point, selectAll: true)
                }
            }
            let copy = UIAction(
                title: "Copy",
                image: UIImage(systemName: "doc.on.doc"),
                identifier: UIAction.Identifier("terminal.copy")
            ) { [weak self] _ in
                _ = self?.copyTouchSelection()
            }
            let pasteItems: [UIMenuElement] = TerminalPasteboardContent.hasContent() ? [paste] : []
            return selecting ? [copy] + pasteItems + [selectAll] : pasteItems + [select, selectAll]
        }
    }
#endif
