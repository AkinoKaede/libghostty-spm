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
            app.launchArguments = ["--ui-testing", "--legacy-selection"]
            installSystemAlertHandler()
            #if !targetEnvironment(macCatalyst)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    XCUIDevice.shared.orientation = .landscapeLeft
                }
            #endif
            app.launch()
        }

        override func tearDownWithError() throws {
            capture("final-state")
            app = nil
        }

        #if !targetEnvironment(macCatalyst)
            func testInlineSingleTapTogglesKeyboardAndKeepsNativeAccessory() throws {
                app.terminate()
                app.launchArguments = ["--ui-testing"]
                app.launch()
                let terminal = try requireTerminalInteractionTarget()
                typeTerminalText("echo tap-keyboard\n", in: terminal)
                XCTAssertTrue(app.buttons["Control"].exists)
                tapTerminal(in: terminal)
                let noFocus = NSPredicate(format: "hasKeyboardFocus == false")
                expectation(for: noFocus, evaluatedWith: terminal)
                waitForExpectations(timeout: 4)
                XCTAssertFalse(app.buttons["Control"].isHittable)
                capture("inline-keyboard-hidden")
                tapTerminal(in: terminal)
                XCTAssertTrue(waitForKeyboardFocus(in: terminal, timeout: 4))
                XCTAssertTrue(app.buttons["Control"].waitForExistence(timeout: 4))
                XCTAssertFalse(app.menuItems["Select"].exists)
                capture("inline-keyboard-shown")
            }

            func testInlineSingleTapClosesMenuBeforeTogglingKeyboard() throws {
                app.terminate()
                app.launchArguments = ["--ui-testing"]
                app.launch()
                let terminal = try requireTerminalInteractionTarget()
                typeTerminalText("echo menu-priority\n", in: terminal)
                terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.15)).press(forDuration: 0.8)
                XCTAssertTrue(app.menuItems["Select"].waitForExistence(timeout: 4))
                terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.8)).tap()
                XCTAssertFalse(app.menuItems["Select"].exists)
                XCTAssertTrue(waitForKeyboardFocus(in: terminal, timeout: 2))
                tapTerminal(in: terminal)
                expectation(for: NSPredicate(format: "hasKeyboardFocus == false"), evaluatedWith: terminal)
                waitForExpectations(timeout: 4)
            }

            func testInlineSelectionMenuAndCopy() throws {
                app.terminate()
                app.launchArguments = ["--ui-testing", "--ui-testing-pasteboard", "--ui-testing-host-menu"]
                app.launch()
                let terminal = try requireTerminalInteractionTarget()
                typeTerminalText("clear\n", in: terminal)
                typeTerminalText("echo inline-selection 你好\n", in: terminal)
                let point = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.025))
                point.press(forDuration: 0.8)
                XCTAssertTrue(app.menuItems["Select"].waitForExistence(timeout: 4), app.debugDescription)
                XCTAssertTrue(app.menuItems["Select All"].exists)
                XCTAssertTrue(app.menuItems["Paste"].exists)
                XCTAssertFalse(selectionTextView().exists)
                capture("inline-selection-menu")
                expandNativeMenuIfNeeded()
                XCTAssertTrue(nativeMenuItem("AutoFill").waitForExistence(timeout: 4), app.debugDescription)
                XCTAssertTrue(nativeMenuItem("Select").exists)
                capture("inline-selection-expanded")
                nativeMenuItem("Select").tap()
                XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4), app.debugDescription)
                XCTAssertTrue(app.menuItems["Select All"].exists)
                XCTAssertTrue(app.menuItems["Paste"].exists)
                capture("inline-selection-word")
                let endHandle = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.04))
                let extended = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.075))
                endHandle.press(forDuration: 0.1, thenDragTo: extended)
                XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4))
                capture("inline-selection-drag")
                app.menuItems["Copy"].tap()
                XCTAssertTrue((copiedSelectionText(in: terminal, timeout: 2) ?? "").contains("inline-selection"))
                // Select again after Copy clears the selection, then expand and Select All.
                point.press(forDuration: 0.8)
                XCTAssertTrue(app.menuItems["Select"].waitForExistence(timeout: 4))
                app.menuItems["Select"].tap()
                XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4))
                expandNativeMenuIfNeeded()
                XCTAssertTrue(nativeMenuItem("AutoFill").waitForExistence(timeout: 4), app.debugDescription)
                XCTAssertTrue(nativeMenuItem("Copy").exists)
                XCTAssertTrue(nativeMenuItem("Select All").exists)
                capture("inline-selection-selected-expanded")
                nativeMenuItem("Select All").tap()
                XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4), app.debugDescription)
                capture("inline-selection-all")
                app.menuItems["Copy"].tap()
                XCTAssertTrue((copiedSelectionText(in: terminal, timeout: 2) ?? "").contains("inline-selection 你好"))

                let output = app.descendants(matching: .any)["terminal.output"].firstMatch
                let viewport = try XCTUnwrap(output.value as? String)
                let nearestLine = try XCTUnwrap(
                    viewport.components(separatedBy: .newlines)
                        .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                )
                // Select from empty space below the prompt, then copy the nearest text row.
                terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8)).press(forDuration: 0.8)
                XCTAssertTrue(app.menuItems["Select"].waitForExistence(timeout: 4))
                app.menuItems["Select"].tap()
                XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4))
                app.menuItems["Copy"].tap()
                let copiedLine = try XCTUnwrap(copiedSelectionText(in: terminal, timeout: 2))
                XCTAssertEqual(
                    copiedLine.trimmingCharacters(in: .whitespacesAndNewlines),
                    nearestLine.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            func testInlineMenuHidesUnavailablePasteAndProvidesHostActions() throws {
                app.terminate()
                app.launchArguments = ["--ui-testing", "--ui-testing-touch-menu"]
                app.launch()
                let terminal = try requireTerminalInteractionTarget()
                typeTerminalText("clear\n", in: terminal)
                typeTerminalText("echo inline-selection\n", in: terminal)
                let point = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.025))
                point.press(forDuration: 0.8)
                XCTAssertTrue(app.menuItems["Select"].waitForExistence(timeout: 4))
                XCTAssertFalse(app.menuItems["Paste"].exists)
                expandNativeMenuIfNeeded()
                XCTAssertTrue(nativeMenuItem("Host Action").waitForExistence(timeout: 4))
                XCTAssertFalse(nativeMenuItem("Inspect Selection").exists)
                XCTAssertFalse(app.staticTexts["Paste"].exists)
                XCTAssertTrue(nativeMenuItem("AutoFill").exists)
                nativeMenuItem("Host Action").tap()
                XCTAssertEqual(terminal.value as? String, "host:none")
                point.press(forDuration: 0.8)
                XCTAssertTrue(app.menuItems["Select"].waitForExistence(timeout: 4))
                app.menuItems["Select"].tap()
                XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4))
                XCTAssertTrue(app.menuItems["Select All"].exists)
                XCTAssertFalse(app.menuItems["Paste"].exists)
                expandNativeMenuIfNeeded()
                XCTAssertTrue(nativeMenuItem("Inspect Selection").waitForExistence(timeout: 4))
                XCTAssertFalse(nativeMenuItem("Host Action").exists)
                XCTAssertTrue(nativeMenuItem("AutoFill").exists)
                XCTAssertFalse(app.staticTexts["Paste"].exists)
                capture("inline-selection-host-menu")
                nativeMenuItem("Inspect Selection").tap()
                XCTAssertTrue((terminal.value as? String ?? "").hasPrefix("host:"))
                XCTAssertNotEqual(terminal.value as? String, "host:none")
            }

            private func expandNativeMenuIfNeeded() {
                let next = app.buttons["Next Page"]
                if next.exists && next.isHittable {
                    next.tap()
                }
            }

            func testInlineDoubleTripleTapAndSelectionDismissal() throws {
                app.terminate()
                app.launchArguments = ["--ui-testing"]
                app.launch()
                let terminal = try requireTerminalInteractionTarget()
                typeTerminalText("clear\n" + String(repeating: "echo gesture-row left middle right\n", count: 25), in: terminal)
                let wordPoint = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
                wordPoint.doubleTap()
                XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4), app.debugDescription)
                app.menuItems["Copy"].tap()
                let word = try XCTUnwrap(copiedSelectionText(in: terminal, timeout: 2))
                XCTAssertFalse(word.contains(" "))
                XCTAssertFalse(word.contains("\n"))
                terminal.tap(withNumberOfTaps: 3, numberOfTouches: 1)
                XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4), app.debugDescription)
                capture("inline-selection-row")
                app.menuItems["Copy"].tap()
                let row = try XCTUnwrap(copiedSelectionText(in: terminal, timeout: 2))
                XCTAssertTrue(row.contains("gesture-row left middle right"), row)
                wordPoint.doubleTap()
                XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4))
                terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
                XCTAssertFalse(app.menuItems["Copy"].exists)
                XCTAssertTrue(waitForKeyboardFocus(in: terminal, timeout: 2))
            }

            func testInlineSelectionScrollsAtBothEdgesAndCopiesHistory() throws {
                app.terminate()
                app.launchArguments = ["--ui-testing"]
                app.launch()
                let terminal = try requireTerminalInteractionTarget()
                let commands = (0 ..< 45).map { String(format: "echo history-%03d left middle right\n", $0) }.joined()
                typeTerminalText("clear\n" + commands, in: terminal)
                let output = app.descendants(matching: .any)["terminal.output"].firstMatch
                func rows(in text: String) -> [Int] {
                    text.components(separatedBy: "history-").dropFirst().compactMap { Int($0.prefix(3)) }
                }
                for edge in [0.003, 0.997] {
                    let before = try XCTUnwrap(output.value as? String)
                    let firstBefore = try XCTUnwrap(rows(in: before).min())
                    terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).doubleTap()
                    XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4))
                    let start = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
                    let end = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: edge))
                    start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 2)
                    XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 4))
                    let after = try XCTUnwrap(output.value as? String)
                    let firstAfter = try XCTUnwrap(rows(in: after).min())
                    if edge < 0.5 {
                        XCTAssertLessThan(firstAfter, firstBefore, after)
                    } else {
                        XCTAssertGreaterThan(firstAfter, firstBefore, after)
                    }
                    capture(edge < 0.5 ? "inline-scroll-top" : "inline-scroll-bottom")
                    app.menuItems["Copy"].tap()
                    let copied = try XCTUnwrap(copiedSelectionText(in: terminal, timeout: 2))
                    let copiedRows = rows(in: copied)
                    if edge < 0.5 {
                        XCTAssertLessThan(try XCTUnwrap(copiedRows.min()), firstBefore, copied)
                    } else {
                        XCTAssertGreaterThan(try XCTUnwrap(copiedRows.max()), try XCTUnwrap(rows(in: before).max()), copied)
                    }
                }
            }

            private func nativeMenuItem(_ title: String) -> XCUIElement {
                let compact = app.menuItems[title]
                return compact.exists ? compact : app.buttons[title]
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
