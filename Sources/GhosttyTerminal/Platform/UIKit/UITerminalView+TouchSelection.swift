#if canImport(UIKit)
    import UIKit

    /// Hosts can supply localized menu titles without putting app copy in the renderer.
    public struct TerminalTouchSelectionTitles {
        public var paste: String
        public var select: String
        public var selectAll: String
        public var copy: String

        public init(
            paste: String = "Paste", select: String = "Select", selectAll: String = "Select All", copy: String = "Copy"
        ) {
            self.paste = paste
            self.select = select
            self.selectAll = selectAll
            self.copy = copy
        }
    }

    struct TouchSelectionState {
        var enabled = false
        var lastInputWasDirect = true
        var titles = TerminalTouchSelectionTitles()
        var range: ClosedRange<Int>?
        var grid: TerminalSelectionGrid?
        weak var surface: TerminalSurface?
        var text: String?
        var menuPoint: CGPoint?
        var menuVisible = false
        var tapRecognizers: [UITapGestureRecognizer] = []
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
        var touchViewportOffset: Int { Int(core.bridge.scrollbar?.offset ?? 0) }

        func touchSelectionGrid() -> TerminalSelectionGrid? {
            guard let surface, let metrics = surface.size(),
                let first = surface.readCells(0...0, columns: Int(metrics.columns), viewport: true)
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
                range = 0...last
            } else if selectLine {
                let start = cell / grid.columns * grid.columns
                range = start...(start + grid.columns - 1)
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

        func dragTouchSelection(_ endpoint: TerminalTouchSelectionOverlay.Endpoint, gesture: UIPanGestureRecognizer) {
            guard let grid = touchSelection.grid, let range = touchSelection.range else { return }
            switch gesture.state {
            case .began:
                if #available(iOS 16.0, *) { selectionEditMenuInteraction.dismissMenu() }
                let cell = endpoint == .start ? range.lowerBound : range.upperBound
                let fixed = endpoint == .start ? range.upperBound : range.lowerBound
                touchSelection.pivot = surface?.glyphCells(at: fixed, columns: grid.columns)
                let rect = grid.rect(for: cell, viewportOffset: touchViewportOffset)
                touchSelection.dragOrigin = CGPoint(x: rect.midX, y: rect.midY)
                touchSelection.endpoint = endpoint
                #if !targetEnvironment(macCatalyst)
                    softwareKeyboard.tapCandidateArmed = false
                #endif
            case .changed, .ended:
                guard let origin = touchSelection.dragOrigin else { return }
                let delta = gesture.translation(in: self)
                let point = CGPoint(x: origin.x + delta.x, y: origin.y + delta.y)
                touchSelection.dragPoint = point
                extendTouchSelection(to: point, endpoint: endpoint)
                if gesture.state == .ended {
                    finishTouchSelectionDrag(at: point)
                } else {
                    startTouchSelectionScrolling()
                }
            case .cancelled, .failed:
                finishTouchSelectionDrag(at: gesture.location(in: self))
            default: break
            }
        }

        func extendTouchSelection(to point: CGPoint, endpoint: TerminalTouchSelectionOverlay.Endpoint) {
            guard let surface, let grid = touchSelection.grid, let range = touchSelection.range else { return }
            let cell = grid.cell(at: point, viewportOffset: touchViewportOffset)
            let glyph = surface.glyphCells(at: cell, columns: grid.columns)
            let fixed =
                touchSelection.pivot
                ?? (endpoint == .start ? range.upperBound...range.upperBound : range.lowerBound...range.lowerBound)
            var updated = min(glyph.lowerBound, fixed.lowerBound)...max(glyph.upperBound, fixed.upperBound)
            if touchSelection.selectsRows {
                let firstCell = updated.lowerBound / grid.columns * grid.columns
                let lastCell = updated.upperBound / grid.columns * grid.columns + grid.columns - 1
                updated = firstCell...lastCell
            }
            guard let text = surface.readCells(updated, columns: grid.columns)?.text else { return }
            touchSelection.range = updated
            touchSelection.text = text
            touchSelection.overlay?.update(grid: grid, range: updated, offset: touchViewportOffset)
        }

        func startTouchSelectionScrolling() {
            guard touchSelection.scrollTask == nil else { return }
            touchSelection.scrollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
                    guard let self, let point = touchSelection.dragPoint, let endpoint = touchSelection.endpoint,
                        let grid = touchSelection.grid, let bar = core.bridge.scrollbar
                    else { return }
                    let top = grid.origin.y + grid.cellSize.height
                    let bottom = grid.origin.y + CGFloat(grid.rows - 1) * grid.cellSize.height
                    let direction = point.y < top ? -1 : (point.y > bottom ? 1 : 0)
                    let row = min(max(0, Int(bar.total) - grid.rows), max(0, touchViewportOffset + direction))
                    if direction != 0, row != touchViewportOffset {
                        _ = surface?.scrollToRow(UInt(row))
                        core.requestImmediateTick()
                        // The next tick publishes the new viewport offset.
                    }
                    extendTouchSelection(to: point, endpoint: endpoint)
                }
            }
        }

        func finishTouchSelectionDrag(at point: CGPoint) {
            touchSelection.scrollTask?.cancel()
            touchSelection.scrollTask = nil
            touchSelection.dragPoint = nil
            touchSelection.dragOrigin = nil
            touchSelection.endpoint = nil
            presentTouchSelectionMenu(at: point)
        }

        func copyTouchSelection() -> Bool {
            guard let range = touchSelection.range, let grid = touchSelection.grid,
                let text = surface?.readCells(range, columns: grid.columns)?.text,
                text == touchSelection.text, !text.isEmpty
            else { return false }
            UIPasteboard.general.string = text
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { accessibilityValue = text }
            #endif
            dismissTouchSelection()
            return true
        }
    }
#endif
