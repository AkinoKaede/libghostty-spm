#if canImport(UIKit)
    #if !targetEnvironment(macCatalyst)
        import UIKit

        extension UITerminalView {
            // Direct-touch grammar: single tap for focus/menu,
            // double tap for a word, triple tap for a row, long press for the menu.
            func setupTouchSelectionGestures() {
                for count in 1...3 {
                    let tap = UITapGestureRecognizer(target: self, action: #selector(handleSelectionTap(_:)))
                    tap.numberOfTapsRequired = count
                    tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                    tap.delegate = self
                    tap.isEnabled = usesInlineTextSelection
                    addGestureRecognizer(tap)
                    touchSelection.tapRecognizers.append(tap)
                }
                touchSelection.tapRecognizers[0].require(toFail: touchSelection.tapRecognizers[1])
                touchSelection.tapRecognizers[1].require(toFail: touchSelection.tapRecognizers[2])
            }

            func updateTouchSelectionGestures() {
                for tap in touchSelection.tapRecognizers { tap.isEnabled = usesInlineTextSelection }
                touchSelection.longPress?.minimumPressDuration = usesInlineTextSelection ? 0.7 : 0.5
                touchSelection.scrollGesture?.maximumNumberOfTouches = usesInlineTextSelection ? 2 : 1
                // Two fingers are reserved for local scrollback in this gesture model.
                for pinch in gestureRecognizers?.compactMap({ $0 as? UIPinchGestureRecognizer }) ?? [] {
                    pinch.isEnabled = !usesInlineTextSelection
                }
            }

            @objc func handleSelectionTap(_ gesture: UITapGestureRecognizer) {
                guard usesInlineTextSelection, gesture.state == .ended, let surface else { return }
                stopMomentumScrolling()
                let point = gesture.location(in: self)
                switch gesture.numberOfTapsRequired {
                case 3:
                    beginTouchSelection(at: point, selectAll: false, selectLine: true)
                case 2:
                    if !isFirstResponder, surface.isMouseCaptured {
                        becomeFirstResponder()
                    } else {
                        beginTouchSelection(at: point, selectAll: false)
                    }
                default:
                    if !isFirstResponder {
                        if surface.isMouseCaptured, touchSelection.range == nil {
                            sendTapClick(at: point)
                        } else {
                            becomeFirstResponder()
                        }
                        return
                    }
                    if touchSelection.range != nil {
                        dismissTouchSelection()
                    } else if surface.isMouseCaptured {
                        sendTapClick(at: point)
                    } else if isTouchMenuVisible {
                        if #available(iOS 16.0, *) {
                            selectionEditMenuInteraction.dismissMenu()
                        } else {
                            UIMenuController.shared.hideMenu()
                        }
                    } else if let grid = touchSelectionGrid() {
                        let cursor = surface.imePoint()
                        let nearCursor =
                            abs(point.x - cursor.x) < grid.cellSize.width * 4
                            && abs(point.y - (cursor.y - grid.cellSize.height / 2)) < grid.cellSize.height * 2
                        if nearCursor { presentTouchMenu(at: point) } else { sendTapClick(at: point) }
                    }
                }
            }

            /// Once selection is active, a one-finger pan extends around a fixed
            /// endpoint; a two-finger pan remains available for local scrollback.
            func handleTouchSelectionPan(_ gesture: UIPanGestureRecognizer) {
                guard let range = touchSelection.range, let grid = touchSelection.grid else { return }
                let point = gesture.location(in: self)
                switch gesture.state {
                case .began:
                    stopMomentumScrolling()
                    if #available(iOS 16.0, *) { selectionEditMenuInteraction.dismissMenu() }
                    let cell = grid.cell(at: point, viewportOffset: touchViewportOffset)
                    func near(_ endpoint: Int) -> Bool {
                        abs(cell % grid.columns - endpoint % grid.columns) < 3
                            && abs(cell / grid.columns - endpoint / grid.columns) < 2
                    }
                    let fixed =
                        near(range.lowerBound)
                        ? range.upperBound
                        : near(range.upperBound)
                            ? range.lowerBound : touchSelection.pivot?.lowerBound ?? range.lowerBound
                    touchSelection.pivot = surface?.glyphCells(at: fixed, columns: grid.columns)
                    touchSelection.endpoint = .end
                case .changed, .ended:
                    touchSelection.dragPoint = point
                    extendTouchSelection(to: point, endpoint: .end)
                    if gesture.state == .ended {
                        finishTouchSelectionDrag(at: point)
                    } else {
                        startTouchSelectionScrolling()
                    }
                case .cancelled, .failed:
                    dismissTouchSelection()
                default: break
                }
            }
        }
    #endif
#endif
