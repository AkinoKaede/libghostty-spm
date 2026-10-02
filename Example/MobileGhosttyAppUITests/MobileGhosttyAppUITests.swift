import XCTest

// These tests drive a UIKit app (iPhone, iPad, Mac Catalyst). The whole file
// sits in the UIKit branch so every `targetEnvironment` check below is nested
// inside it, the order AGENTS.md requires: Catalyst imports UIKit *and*
// AppKit, so UIKit is always asked first.
#if canImport(UIKit)
    import UIKit

    #if targetEnvironment(macCatalyst)
        import AppKit
    #endif

    final class MobileGhosttyAppUITests: XCTestCase {
        private var app: XCUIApplication!

        override func setUpWithError() throws {
            continueAfterFailure = false
            app = XCUIApplication()
            app.launchArguments = ["--ui-testing"]
            installSystemAlertHandler()
            #if !targetEnvironment(macCatalyst)
                XCUIDevice.shared.orientation = launchOrientation
            #endif
            app.launch()
        }

        override func tearDownWithError() throws {
            capture("final-state")
            #if !targetEnvironment(macCatalyst)
                if XCUIDevice.shared.orientation != launchOrientation {
                    XCUIDevice.shared.orientation = launchOrientation
                }
            #endif
            app = nil
        }

        #if !targetEnvironment(macCatalyst)
            private var launchOrientation: UIDeviceOrientation {
                UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
            }
        #endif

        // MARK: - Lifecycle and stress

        func testTypedCommandBurstProducesEveryOutputInOrder() throws {
            let terminal = try requireTerminalInteractionTarget()
            typeTerminalText("clear\n", in: terminal)
            let expected = (1 ... 8).map { String(format: "burst-%02d", $0) }
            let burst = expected.map { "echo \($0)\n" }.joined()
            typeTerminalText(burst, in: terminal)

            let viewport = waitForViewport("all burst outputs") { text in
                Self.outputLines(of: text).filter { $0.hasPrefix("burst-") } == expected
            }
            XCTAssertNotNil(viewport)
            capture("burst-output")
        }

        func testBackgroundForegroundKeepsTerminalUsable() throws {
            let terminal = try requireTerminalInteractionTarget()
            typeTerminalText("echo before-background\n", in: terminal)
            waitForOutputLine("before-background")

            for cycle in 1 ... 3 {
                sendAppToBackgroundAndBack()
                capture("foreground-\(cycle)")
                XCTAssertTrue(
                    Self.outputLines(of: viewportText()).contains("before-background"),
                    "Earlier output was lost after background cycle \(cycle)"
                )
                typeTerminalText("echo after-foreground-\(cycle)\n", in: terminal)
                waitForOutputLine("after-foreground-\(cycle)")
            }
        }

        func testLongOutputScrollsBackAndReturnsOnTyping() throws {
            let terminal = try requireTerminalInteractionTarget()
            typeTerminalText(String(repeating: "help\n", count: 6) + "echo long-output-done\n", in: terminal)
            // Trimmed lines lose the prompt's trailing space.
            let bottom = waitForViewport("six help blocks") { text in
                let lines = Self.outputLines(of: text)
                return lines.contains("long-output-done") && lines.last?.hasSuffix("%") == true
            }
            let bottomText = try XCTUnwrap(bottom)

            scrollTerminalIntoHistory(terminal)
            waitForViewport("viewport scrolled into history") { $0 != bottomText }
            capture("scrolled-into-history")

            typeTerminalText("echo after-scroll\n", in: terminal)
            waitForOutputLine("after-scroll")
            capture("scrolled-back-on-typing")
        }

        func testRelaunchStartsAFreshUsableTerminal() throws {
            var terminal = try requireTerminalInteractionTarget()
            typeTerminalText("echo before-relaunch\n", in: terminal)
            waitForOutputLine("before-relaunch")

            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

            terminal = try requireTerminalInteractionTarget()
            let fresh = waitForViewport("welcome banner after relaunch") {
                $0.contains("GhosttyKit Sandbox Demo")
            }
            XCTAssertFalse(fresh?.contains("before-relaunch") ?? true)
            typeTerminalText("echo after-relaunch\n", in: terminal)
            waitForOutputLine("after-relaunch")
        }

        #if targetEnvironment(macCatalyst)
            func testWindowResizeChangesGridAndKeepsTerminalUsable() throws {
                let terminal = try requireTerminalInteractionTarget()
                let original = try XCTUnwrap(terminalGridSize(in: terminal))

                let window = app.windows.firstMatch
                let originalWidth = window.frame.width
                // The left edge: a window as wide as the screen has its right
                // edge on the display border, where a drag does not resize.
                dragWindowLeftEdge(window, by: 240)
                waitForFrameWidth(of: window) { $0 < originalWidth - 100 }
                let narrowed = try XCTUnwrap(terminalGridSize(in: terminal))
                XCTAssertLessThan(narrowed.columns, original.columns)
                capture("window-narrowed")

                dragWindowLeftEdge(window, by: -240)
                waitForFrameWidth(of: window) { $0 > originalWidth - 20 }
                let restored = try XCTUnwrap(terminalGridSize(in: terminal))
                XCTAssertGreaterThan(restored.columns, narrowed.columns)
                typeTerminalText("echo after-resize\n", in: terminal)
                waitForOutputLine("after-resize")
            }
        #else
            func testRotationResizesGridAndKeepsTerminalUsable() throws {
                let terminal = try requireTerminalInteractionTarget()
                let original = try XCTUnwrap(terminalGridSize(in: terminal))
                let rotated: UIDeviceOrientation = isIPad ? .portrait : .landscapeLeft

                XCUIDevice.shared.orientation = rotated
                let turned = try XCTUnwrap(waitForGridSize(in: terminal) { $0.columns != original.columns })
                if isIPad {
                    XCTAssertLessThan(turned.columns, original.columns)
                } else {
                    XCTAssertGreaterThan(turned.columns, original.columns)
                }
                capture("rotated")
                typeTerminalText("echo rotated\n", in: terminal)
                waitForOutputLine("rotated")

                XCUIDevice.shared.orientation = launchOrientation
                let restored = try XCTUnwrap(waitForGridSize(in: terminal) { $0.columns == original.columns })
                XCTAssertEqual(restored.columns, original.columns)
                typeTerminalText("echo rotated-back\n", in: terminal)
                waitForOutputLine("rotated-back")
            }

            func testSoftwareKeyboardToggleResizesAndKeepsTerminalUsable() throws {
                let terminal = try requireTerminalInteractionTarget()
                XCTAssertTrue(prepareTerminalForTyping(terminal))
                let keyboard = app.keyboards.firstMatch
                guard keyboard.waitForExistence(timeout: 3) else {
                    throw XCTSkip("No software keyboard: the simulator has a hardware keyboard connected")
                }
                let shownGrid = try XCTUnwrap(terminalGridSize(in: terminal))
                let shownHeight = terminal.frame.height

                for cycle in 1 ... 3 {
                    tapTerminal(in: terminal)
                    XCTAssertTrue(keyboard.waitForNonExistence(timeout: 4), "Keyboard stayed up, cycle \(cycle)")
                    XCTAssertGreaterThan(terminal.frame.height, shownHeight, "Terminal did not grow, cycle \(cycle)")
                    tapTerminal(in: terminal)
                    XCTAssertTrue(keyboard.waitForExistence(timeout: 4), "Keyboard did not return, cycle \(cycle)")
                }
                capture("keyboard-toggled")

                let finalGrid = try XCTUnwrap(terminalGridSize(in: terminal))
                XCTAssertEqual(finalGrid, shownGrid)
                typeTerminalText("echo after-keyboard-toggle\n", in: terminal)
                waitForOutputLine("after-keyboard-toggle")
            }
        #endif

        // MARK: - Lifecycle helpers

        private struct GridSize: Equatable {
            var columns: Int
            var rows: Int
        }

        private var outputElement: XCUIElement {
            app.descendants(matching: .any)["terminal.output"].firstMatch
        }

        private func viewportText() -> String {
            (outputElement.value as? String) ?? ""
        }

        private static func outputLines(of viewport: String) -> [String] {
            viewport.components(separatedBy: "\n").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
        }

        @discardableResult
        private func waitForViewport(
            _ description: String,
            timeout: TimeInterval = 8,
            until condition: (String) -> Bool
        ) -> String? {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                let text = viewportText()
                if condition(text) {
                    return text
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            } while Date() < deadline
            log("viewport-timeout", "\(description)\n---\n\(viewportText())")
            XCTFail("Viewport never showed: \(description)")
            return nil
        }

        private func waitForOutputLine(_ line: String) {
            waitForViewport("output line \(line)") {
                Self.outputLines(of: $0).contains(line)
            }
        }

        /// Clears the screen and runs `size`, so the one `columns:` line on
        /// screen is the grid the shell sees now.
        private func terminalGridSize(in terminal: XCUIElement) -> GridSize? {
            typeTerminalText("clear\nsize\n", in: terminal)
            var grid: GridSize?
            waitForViewport("size output") { text in
                grid = Self.parseGridSize(text)
                return grid != nil
            }
            return grid
        }

        private func waitForGridSize(
            in terminal: XCUIElement,
            timeout: TimeInterval = 10,
            until condition: (GridSize) -> Bool
        ) -> GridSize? {
            let deadline = Date().addingTimeInterval(timeout)
            var last: GridSize?
            repeat {
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                last = terminalGridSize(in: terminal)
                if let last, condition(last) {
                    return last
                }
            } while Date() < deadline
            XCTFail("Grid size never reached the expected value; last \(String(describing: last))")
            return nil
        }

        private static func parseGridSize(_ viewport: String) -> GridSize? {
            for line in outputLines(of: viewport).reversed() where line.hasPrefix("columns: ") {
                let numbers = line.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                guard numbers.count >= 2 else { continue }
                return GridSize(columns: numbers[0], rows: numbers[1])
            }
            return nil
        }

        private func sendAppToBackgroundAndBack() {
            #if targetEnvironment(macCatalyst)
                // A Cmd+H sent while the app is still settling after the
                // previous unhide can be dropped; one retry tells that apart
                // from an app that cannot hide.
                var result = XCTWaiter.Result.timedOut
                for _ in 1 ... 2 where result != .completed {
                    app.typeKey("h", modifierFlags: .command)
                    let hidden = XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "isHittable == false"),
                        object: app.windows.firstMatch
                    )
                    result = XCTWaiter.wait(for: [hidden], timeout: 5)
                }
                XCTAssertEqual(result, .completed)
                app.activate()
                XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
            #else
                XCUIDevice.shared.press(.home)
                let backgrounded = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "state != %d", XCUIApplication.State.runningForeground.rawValue),
                    object: app
                )
                XCTAssertEqual(XCTWaiter.wait(for: [backgrounded], timeout: 8), .completed)
                app.activate()
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            #endif
        }

        private func scrollTerminalIntoHistory(_ terminal: XCUIElement) {
            #if targetEnvironment(macCatalyst)
                terminal.scroll(byDeltaX: 0, deltaY: 300)
            #else
                terminal.swipeDown(velocity: .fast)
            #endif
        }

        #if targetEnvironment(macCatalyst)
            private func dragWindowLeftEdge(_ window: XCUIElement, by dx: CGFloat) {
                let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
                    .withOffset(CGVector(dx: 1, dy: 0))
                edge.press(forDuration: 0.3, thenDragTo: edge.withOffset(CGVector(dx: dx, dy: 0)))
            }

            private func waitForFrameWidth(of window: XCUIElement, _ condition: (CGFloat) -> Bool) {
                let deadline = Date().addingTimeInterval(5)
                while Date() < deadline {
                    if condition(window.frame.width) { return }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
                }
                XCTFail("Window width never changed as expected; now \(window.frame.width)")
            }
        #endif

        func testTerminalUserOperations() throws {
            let terminal = try requireTerminalInteractionTarget()

            capture("01-launch")
            typeTerminalText("uname\n", in: terminal)
            let output = app.descendants(matching: .any)["terminal.output"].firstMatch
            XCTAssertTrue(output.waitForExistence(timeout: 4))
            let expectedReturnOutput = "Darwin ghostty-sandbox host-managed"
            let outputExpectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value CONTAINS %@", expectedReturnOutput),
                object: output
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [outputExpectation], timeout: 4),
                .completed
            )
            let viewport = try XCTUnwrap(output.value as? String)
            XCTAssertEqual(viewport.nonOverlappingCount(of: expectedReturnOutput), 1)
            capture("02-single-line-input")

            typeTerminalText("echo first line\n", in: terminal)
            typeTerminalText("echo second line\n", in: terminal)
            capture("03-multiple-lines")

            typeTerminalText("中文键盘测试，标点和全角字符。\n", in: terminal)
            capture("04-chinese-input")

            typeTerminalText("日本語キーボードテスト、かなと漢字。\n", in: terminal)
            capture("05-japanese-input")

            typeTerminalText("Mixed input: English 中文 日本語 123\n", in: terminal)
            capture("06-multilingual-input")

            tapTerminal(in: terminal)
            capture("07-tap-dismiss-keyboard")
            tapTerminal(in: terminal)
            capture("08-tap-refocus")

            typeTerminalText("help\n", in: terminal)
            capture("09-help-output")

            terminal.swipeUp()
            capture("10-swipe-up")
            terminal.swipeDown()
            capture("11-swipe-down")

            #if targetEnvironment(macCatalyst)
                app.typeKey("=", modifierFlags: .command)
            #else
                terminal.pinch(withScale: 1.25, velocity: 1.0)
            #endif
            capture("12-zoom-in")
            // Use the keyboard zoom-out path on iOS because XCTest's second
            // pinch in one test session can report an invalid coordinate.
            app.typeKey("-", modifierFlags: .command)
            capture("13-zoom-out")

            typeTerminalText("clear\n", in: terminal)
            capture("14-clear-command")

            let pointerSelectionCommand: String
            #if targetEnvironment(macCatalyst)
                pointerSelectionCommand = "echo \(catalystPointerSelectionPrefix)\(expectedPointerSelection)\n"
            #else
                pointerSelectionCommand = isIPad
                    ? "echo \(iPadPointerSelectionPrefix)\(expectedPointerSelection)\n"
                    : "echo \(expectedPointerSelection)\n"
            #endif
            typeTerminalText(pointerSelectionCommand, in: terminal)
            #if targetEnvironment(macCatalyst)
                dragPointerSelection(in: terminal)
                capture("15-pointer-selection-catalyst")
                openCopyMenuAndCopySelection(in: terminal, screenshotName: "16-pointer-copy-menu-catalyst")
                longPressTerminal(in: terminal)
                capture("17-long-press-catalyst")
            #else
                if isIPad {
                    longPressTerminal(in: terminal, offset: CGVector(dx: 0.35, dy: 0.18))
                    XCTAssertTrue(selectionTextView().waitForExistence(timeout: 4))
                    capture("15-long-press-selection")
                    dismissSelectionSheet()

                    hideSoftwareKeyboardIfVisible()
                    capture("16-ipad-keyboard-hidden-before-pointer")
                    let rightClick = dragIPadPointerSelection(in: terminal)
                    capture("17-ipad-pointer-selection")
                    openCopyMenuAndCopySelection(
                        in: terminal,
                        screenshotName: "18-ipad-pointer-copy-menu",
                        rightClickCoordinate: rightClick
                    )
                } else {
                    longPressTerminal(in: terminal, offset: CGVector(dx: 0.35, dy: 0.18))
                    XCTAssertTrue(selectionTextView().waitForExistence(timeout: 4))
                    capture("15-long-press-selection")
                }
            #endif

            #if !targetEnvironment(macCatalyst)
                if isIPad {
                    tapTerminal(in: terminal)
                    tapAccessoryButton("Tab", screenshotName: "16-accessory-tab")
                    tapAccessoryButton("Escape", screenshotName: "17-accessory-esc")
                    tapAccessoryButton("Right Arrow", screenshotName: "18-accessory-right")
                }
            #endif

            #if targetEnvironment(macCatalyst)
                openThemeMenuAndSelectPopularTheme()
                capture("19-theme-menu-selection")
            #else
                if isIPad {
                    openThemeMenuAndSelectPopularTheme()
                    capture("19-theme-menu-selection")
                }
            #endif
        }

        private func installSystemAlertHandler() {
            addUIInterruptionMonitor(withDescription: "System alert") { alert in
                let preferredButtons = [
                    "OK", "Ok", "好", "确定", "允许", "Allow", "继续", "Continue",
                    "关闭", "Close", "Dismiss",
                ]
                for title in preferredButtons {
                    let button = alert.buttons[title].firstMatch
                    if button.exists {
                        self.activateInterruptionButton(button)
                        return true
                    }
                }

                let firstButton = alert.buttons.firstMatch
                guard firstButton.exists else { return false }
                if firstButton.identifier == "InputSource" ||
                    firstButton.label.hasPrefix("com.apple.inputmethod.")
                {
                    self.app.typeKey(.escape, modifierFlags: [])
                    return true
                }
                self.activateInterruptionButton(firstButton)
                return true
            }
        }

        private func activateInterruptionButton(_ button: XCUIElement) {
            #if targetEnvironment(macCatalyst)
                button.click()
            #else
                button.tap()
            #endif
        }

        private func requireTerminalInteractionTarget() throws -> XCUIElement {
            let terminal = app.descendants(matching: .any)["terminal.surface"].firstMatch
            if terminal.waitForExistence(timeout: 4), terminal.isHittable {
                return terminal
            }

            let window = app.windows.firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 8))
            XCTAssertTrue(window.isHittable)
            return window
        }

        private func tapTerminal(in element: XCUIElement) {
            let coordinate = element.coordinate(withNormalizedOffset: terminalInteractionOffset)
            #if targetEnvironment(macCatalyst)
                coordinate.click()
            #else
                if isIPad {
                    coordinate.tap()
                } else {
                    coordinate.press(forDuration: 0.01)
                }
            #endif
        }

        private func typeTerminalText(_ text: String, in element: XCUIElement) {
            #if targetEnvironment(macCatalyst)
                element.coordinate(withNormalizedOffset: terminalInteractionOffset).click()
                app.typeText(text)
            #else
                if !isIPad, !prepareTerminalForTyping(element) {
                    return
                }
                element.typeText(text)
            #endif
        }

        #if !targetEnvironment(macCatalyst)
            private func prepareTerminalForTyping(_ element: XCUIElement) -> Bool {
                if selectionTextView().exists {
                    dismissSelectionSheet()
                }
                if waitForKeyboardFocus(in: element, timeout: 0.5) {
                    return true
                }

                for _ in 0 ..< 2 {
                    tapTerminal(in: element)
                    if selectionTextView().waitForExistence(timeout: 0.25) {
                        dismissSelectionSheet()
                    }
                    if waitForKeyboardFocus(in: element, timeout: 2) {
                        return true
                    }
                }
                XCTFail("Terminal did not acquire keyboard focus before typing")
                return false
            }

            private func waitForKeyboardFocus(
                in element: XCUIElement,
                timeout: TimeInterval
            ) -> Bool {
                let expectation = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "hasKeyboardFocus == true"),
                    object: element
                )
                return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
            }
        #endif

        private func longPressTerminal(in element: XCUIElement, offset: CGVector? = nil) {
            element.coordinate(withNormalizedOffset: offset ?? terminalInteractionOffset).press(forDuration: 0.7)
        }

        #if targetEnvironment(macCatalyst)
            private func dragPointerSelection(in element: XCUIElement) {
                log(
                    "pointer-selection-coordinates",
                    "start=(0.008, 0.045), end=(0.42, 0.045), rightClick=(0.20, 0.045)"
                )
                let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.008, dy: 0.045))
                let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.045))
                start.press(forDuration: 0.1, thenDragTo: end)
            }
        #else
            private var isIPad: Bool {
                UIDevice.current.userInterfaceIdiom == .pad
            }

            /// Returns the right-click coordinate for the follow-up copy menu.
            ///
            /// The drag's own click makes the terminal first responder, which
            /// summons the software keyboard and shrinks the terminal mid-drag.
            /// A normalized offset resolved *after* that (the right click) would
            /// use the post-keyboard frame and land on a different row than the
            /// selection. Snapshot the frame once and convert every point to a
            /// screen-absolute coordinate so all events target the same spot —
            /// the text itself does not move when the view shrinks.
            private func dragIPadPointerSelection(in element: XCUIElement) -> XCUICoordinate {
                let frame = element.frame
                log(
                    "ipad-pointer-selection-coordinates",
                    "frame=\(frame) command=echo \(iPadPointerSelectionPrefix)\(expectedPointerSelection) start=(0.015, 0.035), end=(0.205, 0.035), rightClick=(0.10, 0.035)"
                )
                let start = screenCoordinate(in: frame, dx: 0.015, dy: 0.035)
                let end = screenCoordinate(in: frame, dx: 0.205, dy: 0.035)
                let rightClick = screenCoordinate(in: frame, dx: 0.10, dy: 0.035)
                start.click(forDuration: 0.1, thenDragTo: end)
                return rightClick
            }

            private func screenCoordinate(
                in frame: CGRect,
                dx: CGFloat,
                dy: CGFloat
            ) -> XCUICoordinate {
                app.coordinate(withNormalizedOffset: .zero).withOffset(
                    CGVector(
                        dx: frame.minX + frame.width * dx,
                        dy: frame.minY + frame.height * dy
                    )
                )
            }

            private func hideSoftwareKeyboardIfVisible() {
                let hideKeyboard = app.buttons["Hide keyboard"].firstMatch
                if hideKeyboard.waitForExistence(timeout: 1), hideKeyboard.isHittable {
                    hideKeyboard.tap()
                    XCTAssertFalse(hideKeyboard.waitForExistence(timeout: 2))
                }
            }
        #endif

        private func openCopyMenuAndCopySelection(
            in element: XCUIElement,
            screenshotName: String,
            rightClickCoordinate: XCUICoordinate? = nil
        ) {
            UIPasteboard.general.string = nil
            let coordinate: XCUICoordinate
            if let rightClickCoordinate {
                log("pointer-copy-menu-coordinate", "screen-absolute right click from drag snapshot")
                coordinate = rightClickCoordinate
            } else {
                let offset = CGVector(dx: 0.20, dy: 0.045)
                log("pointer-copy-menu-coordinate", "frame=\(element.frame) rightClick=(\(offset.dx), \(offset.dy))")
                coordinate = element.coordinate(withNormalizedOffset: offset)
            }
            coordinate.rightClick()
            let copy = copyMenuItem()
            if !copy.waitForExistence(timeout: 3) {
                capture("\(screenshotName)-missing")
                XCTFail(
                    "Copy menu item not found after pointer selection right click. Hierarchy: \(app.debugDescription)"
                )
                return
            }
            capture(screenshotName)
            activateCopyMenuItem(copy)
            let actual = copiedSelectionText(in: element, timeout: 2)
            log("pointer-selection-pasteboard", actual ?? "<nil>")
            XCTAssertEqual(actual, expectedPointerSelection)
        }

        private func activateCopyMenuItem(_ copy: XCUIElement) {
            #if targetEnvironment(macCatalyst)
                copy.click()
            #else
                copy.tap()
            #endif
        }

        private func copyMenuItem() -> XCUIElement {
            #if targetEnvironment(macCatalyst)
                app.menuItems["Copy"].firstMatch
            #else
                app.buttons["Copy"].firstMatch
            #endif
        }

        private func copiedSelectionText(in element: XCUIElement, timeout: TimeInterval) -> String? {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                if let string = copiedSelectionTextSnapshot(in: element, timeout: 0.25) {
                    return string
                }
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            } while Date() < deadline
            return nil
        }

        private func copiedSelectionTextSnapshot(in element: XCUIElement, timeout: TimeInterval) -> String? {
            #if !targetEnvironment(macCatalyst)
                return element.value as? String
            #else
                _ = timeout
                return UIPasteboard.general.string
            #endif
        }

        private func log(_ name: String, _ value: String) {
            let attachment = XCTAttachment(string: value)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        #if targetEnvironment(macCatalyst)
            private var isIPad: Bool {
                false
            }
        #endif

        private var terminalInteractionOffset: CGVector {
            CGVector(dx: 0.5, dy: 0.55)
        }

        private func tapAccessoryButton(_ label: String, screenshotName: String) {
            dismissKeyboardOnboardingIfVisible()
            let button = app.buttons[label]
            guard button.waitForExistence(timeout: 2), button.isHittable else {
                capture("\(screenshotName)-not-visible")
                return
            }
            button.tap()
            capture(screenshotName)
        }

        private func dismissKeyboardOnboardingIfVisible() {
            let continueButton = app.buttons["Continue"].firstMatch
            guard continueButton.waitForExistence(timeout: 1), continueButton.isHittable else {
                return
            }
            #if targetEnvironment(macCatalyst)
                continueButton.click()
            #else
                continueButton.tap()
            #endif
        }

        private func openThemeMenuAndSelectPopularTheme() {
            let themeButton = app.buttons["terminal.themeButton"].firstMatch
            guard themeButton.waitForExistence(timeout: 2), themeButton.isHittable else {
                capture("theme-button-not-visible")
                return
            }
            themeButton.tap()
            capture("theme-menu-open")

            let popular = app.buttons["Popular"].firstMatch
            if popular.waitForExistence(timeout: 1), popular.isHittable {
                popular.tap()
                capture("theme-menu-popular")
            }

            let dracula = app.buttons["Dracula"].firstMatch
            if dracula.waitForExistence(timeout: 2), dracula.isHittable {
                dracula.tap()
            } else {
                capture("theme-dracula-not-visible")
                dismissOpenMenu()
            }
        }

        private func dismissOpenMenu() {
            #if targetEnvironment(macCatalyst)
                app.typeKey(.escape, modifierFlags: [])
            #else
                let window = app.windows.firstMatch
                guard window.exists else { return }
                window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
            #endif
        }

        private func dismissSelectionSheet() {
            let done = app.buttons["terminal.selectionDoneButton"].firstMatch
            if done.waitForExistence(timeout: 2), done.isHittable {
                done.tap()
                XCTAssertTrue(selectionTextView().waitForNonExistence(timeout: 3))
            }
        }

        private func selectionTextView() -> XCUIElement {
            app.textViews["terminal.selectionTextView"].firstMatch
        }

        private func capture(_ name: String) {
            guard let app else { return }
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        private var expectedPointerSelection: String {
            "selection anchor"
        }

        private var iPadPointerSelectionPrefix: String {
            // iPadOS/XCTest clamps the indirect pointer drag start a couple of
            // cells inside the view edge. The prefix keeps the single fixed drag
            // selecting the same expected terminal text without retries.
            "xx"
        }

        #if targetEnvironment(macCatalyst)
            private var catalystPointerSelectionPrefix: String {
                // Mac Catalyst clamps the left-edge pointer drag inside the first
                // text cell on GitHub runners. The prefix keeps the copied text
                // anchored to the same expected selection.
                "x"
            }
        #endif
    }

    private extension String {
        func nonOverlappingCount(of needle: String) -> Int {
            guard !needle.isEmpty else { return 0 }
            var count = 0
            var searchStart = startIndex
            while searchStart < endIndex,
                  let range = range(of: needle, range: searchStart ..< endIndex)
            {
                count += 1
                searchStart = range.upperBound
            }
            return count
        }
    }
#endif
