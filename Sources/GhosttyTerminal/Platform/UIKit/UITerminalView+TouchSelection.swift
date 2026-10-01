//
//  UITerminalView+TouchSelection.swift
//  libghostty-spm
//

#if canImport(UIKit)
    import UIKit

    struct TouchSelectionState {
        var enabled = false
        var lastInputWasDirect = true
        var range: ClosedRange<Int>?
        var grid: TerminalSelectionGrid?
        weak var surface: TerminalSurface?
        var text: String?
        var menuPoint: CGPoint?
        var menuVisible = false
        var tapRecognizers: [UITapGestureRecognizer] = []
        var tapBeganWithMenu = false
        var longPress: UILongPressGestureRecognizer?
        var scrollGesture: UIPanGestureRecognizer?
        var panUsesSelection = false
        var pivot: ClosedRange<Int>?
        var selectsRows = false
        var pendingAction: (() -> Void)?
        var overlay: TerminalTouchSelectionOverlay?
        var dragPoint: CGPoint?
        var dragOrigin: CGPoint?
        var endpoint: TerminalTouchSelectionOverlay.Endpoint?
        var scrollTask: Task<Void, Never>?
        var lastValidation: TimeInterval = 0
    }

    extension UITerminalView {
        var touchViewportOffset: Int {
            Int(core.bridge.scrollbar?.offset ?? 0)
        }

        func touchSelectionGrid() -> TerminalSelectionGrid? {
            guard let surface, let metrics = surface.size(),
                  let first = surface.readCells(0 ... 0, columns: Int(metrics.columns), viewport: true)
            else { return nil }
            return TerminalSelectionGrid(
                metrics: metrics, scale: resolvedDisplayScale(),
                firstBaseline: first.firstBaseline, imeBottom: surface.imePoint().y
            )
        }

        func beginTouchSelection(at point: CGPoint, selectAll: Bool, selectLine: Bool = false) {
            guard usesInlineTextSelection, window != nil, let surface, let grid = touchSelectionGrid() else { return }
            stopMomentumScrolling()
            let cell = grid.cell(at: point, viewportOffset: touchViewportOffset)
            let total = max(grid.rows, Int(core.bridge.scrollbar?.total ?? UInt64(grid.rows)))
            let range: ClosedRange<Int>
            if selectAll {
                guard let last = surface.lastTextCell(rows: total, columns: grid.columns) else { return }
                range = 0 ... last
            } else if selectLine {
                let start = cell / grid.columns * grid.columns
                range = start ... (start + grid.columns - 1)
            } else {
                range = surface.wordCells(at: cell, columns: grid.columns)
            }
            guard let text = surface.readCells(range, columns: grid.columns)?.text, !text.isEmpty else { return }
            dismissTouchSelection()
            // Touch selection owns its highlight; never synthesize mouse events
            // (even Shift can be captured by a TUI).
            _ = surface.performBindingAction("clear_selection")
            touchSelection.range = range
            touchSelection.grid = grid
            touchSelection.surface = surface
            touchSelection.text = text
            touchSelection.pivot = surface.glyphCells(at: range.lowerBound, columns: grid.columns)
            touchSelection.selectsRows = selectLine
            touchSelection.menuPoint = point
            let overlay = TerminalTouchSelectionOverlay(frame: bounds)
            overlay.onDrag = { [weak self] endpoint, gesture in self?.dragTouchSelection(endpoint, gesture: gesture) }
            touchSelection.overlay = overlay
            addSubview(overlay)
            overlay.update(grid: grid, range: range, offset: touchViewportOffset)
            presentTouchSelectionMenu(at: point)
        }

        func dismissTouchSelection() {
            guard touchSelection.range != nil || touchSelection.overlay != nil || isTouchMenuVisible else {
                return
            }
            touchSelection.scrollTask?.cancel()
            touchSelection.scrollTask = nil
            touchSelection.overlay?.removeFromSuperview()
            touchSelection.overlay = nil
            touchSelection.range = nil
            touchSelection.grid = nil
            touchSelection.text = nil
            touchSelection.surface = nil
            touchSelection.dragPoint = nil
            touchSelection.dragOrigin = nil
            touchSelection.endpoint = nil
            touchSelection.pivot = nil
            touchSelection.panUsesSelection = false
            if #available(iOS 16.0, *), touchSelection.enabled {
                selectionEditMenuInteraction.dismissMenu()
            } else if touchSelection.enabled {
                UIMenuController.shared.hideMenu()
            }
        }

        func refreshTouchSelection() {
            guard let range = touchSelection.range, let grid = touchSelection.grid else { return }
            guard surface === touchSelection.surface, let metrics = surface?.size(),
                  Int(metrics.columns) == grid.columns, Int(metrics.rows) == grid.rows,
                  CGFloat(metrics.cellWidthPixels) / resolvedDisplayScale() == grid.cellSize.width,
                  CGFloat(metrics.cellHeightPixels) / resolvedDisplayScale() == grid.cellSize.height
            else {
                dismissTouchSelection()
                return
            }
            let now = Date.timeIntervalSinceReferenceDate
            if now - touchSelection.lastValidation > 0.25, touchSelection.dragPoint == nil {
                touchSelection.lastValidation = now
                guard surface?.readCells(range, columns: grid.columns)?.text == touchSelection.text else {
                    dismissTouchSelection()
                    return
                }
            }
            touchSelection.overlay?.frame = bounds
            touchSelection.overlay?.update(grid: grid, range: range, offset: touchViewportOffset)
        }

        func copyTouchSelection() -> Bool {
            guard let range = touchSelection.range, let grid = touchSelection.grid,
                  let text = surface?.readCells(range, columns: grid.columns)?.text,
                  text == touchSelection.text, !text.isEmpty
            else { return false }
            UIPasteboard.general.string = text
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                    accessibilityValue = text
                }
            #endif
            dismissTouchSelection()
            return true
        }
    }
#endif
