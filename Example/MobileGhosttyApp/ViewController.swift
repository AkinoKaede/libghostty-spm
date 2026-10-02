import GhosttyTerminal
import GhosttyTheme
import ShellCraftKit
import UIKit

final class ViewController: UIViewController {
    private static let lightThemeKey = "SelectedTheme.light"
    private static let darkThemeKey = "SelectedTheme.dark"

    private lazy var terminalView: TerminalView = .init(frame: .zero)
    private lazy var shellSession: ShellSession = .init(shell: defaultSandboxShell)
    private var isKeyboardVisible = false
    private lazy var controller: TerminalController = .init(
        theme: Self.savedTerminalTheme()
    ) { builder in
        builder.withBackgroundOpacity(0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Terminal"
        view.isOpaque = true
        configureTerminalView()
        configureThemeMenu()
        applyBackgroundForCurrentAppearance()
        observeSoftwareKeyboard()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        activateTerminal()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        terminalView.fitToSize()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        controller.setTheme(Self.savedTerminalTheme())
        applyBackgroundForCurrentAppearance()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.updateNavigationBarVisibility(animated: false)
        }
    }

    private func configureTerminalView() {
        terminalView.delegate = self
        terminalView.isAccessibilityElement = true
        terminalView.accessibilityIdentifier = "terminal.surface"
        terminalView.accessibilityLabel = "Terminal"
        terminalView.configuration = TerminalSurfaceOptions(
            backend: .inMemory(shellSession.terminalSession)
        )
        terminalView.controller = controller
        terminalView.backgroundColor = .clear
        terminalView.isOpaque = false
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            // The safe area, not the view edges: in landscape the sensor
            // housing and the rounded corners sit over the first and last
            // columns. The view's background fills the margins.
            terminalView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let output = TerminalOutputAccessibilityView(
                    session: shellSession.terminalSession
                )
                output.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(output)
                NSLayoutConstraint.activate([
                    output.topAnchor.constraint(equalTo: view.topAnchor),
                    output.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    output.widthAnchor.constraint(equalToConstant: 1),
                    output.heightAnchor.constraint(equalToConstant: 1),
                ])
            }
        #endif
    }

    // MARK: - Compact Height

    /// A landscape iPhone with the keyboard and the accessory bar up leaves
    /// one terminal row under the navigation bar, so the bar steps aside
    /// while the keyboard is up there and comes back with the theme menu
    /// when a tap on the terminal puts the keyboard away.
    private func observeSoftwareKeyboard() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow() {
        isKeyboardVisible = true
        updateNavigationBarVisibility(animated: true)
    }

    @objc private func keyboardWillHide() {
        isKeyboardVisible = false
        updateNavigationBarVisibility(animated: true)
    }

    private func updateNavigationBarVisibility(animated: Bool) {
        guard let navigationController else { return }
        let hidden = isKeyboardVisible && view.window?.traitCollection.verticalSizeClass == .compact
        guard navigationController.isNavigationBarHidden != hidden else { return }
        navigationController.setNavigationBarHidden(hidden, animated: animated)
    }

    private func activateTerminal() {
        terminalView.becomeFirstResponder()
        shellSession.start()
    }

    // MARK: - Persistence

    private static func savedTerminalTheme() -> TerminalTheme {
        let lightConfig = savedThemeDefinition(forKey: lightThemeKey)?
            .toTerminalConfiguration() ?? .alabaster
        let darkConfig = savedThemeDefinition(forKey: darkThemeKey)?
            .toTerminalConfiguration() ?? .afterglow
        return TerminalTheme(light: lightConfig, dark: darkConfig)
    }

    private static func savedThemeDefinition(
        forKey key: String
    ) -> GhosttyThemeDefinition? {
        guard let name = UserDefaults.standard.string(forKey: key) else {
            return nil
        }
        return GhosttyThemeCatalog.theme(named: name)
    }

    private var isDarkMode: Bool {
        traitCollection.userInterfaceStyle == .dark
    }

    private func saveTheme(_ theme: GhosttyThemeDefinition) {
        let key = isDarkMode ? Self.darkThemeKey : Self.lightThemeKey
        UserDefaults.standard.set(theme.name, forKey: key)
    }

    private func applyBackgroundForCurrentAppearance() {
        let key = isDarkMode ? Self.darkThemeKey : Self.lightThemeKey
        // Backgrounds of the `.afterglow` / `.alabaster` fallbacks in savedTerminalTheme().
        let defaultBackground = isDarkMode ? "212121" : "F7F7F7"
        // Foregrounds of the same fallbacks.
        let defaultForeground = isDarkMode ? "D0D0D0" : "000000"
        let theme = Self.savedThemeDefinition(forKey: key)
        if let bgColor = UIColor(hexString: theme?.background ?? defaultBackground) {
            view.backgroundColor = bgColor
        }
        // A dark theme picked in light mode (or the reverse) puts the
        // system-colored title on a background of the opposite shade, so
        // the bar takes the theme's foreground instead.
        let foreground = UIColor(hexString: theme?.foreground ?? defaultForeground) ?? .label
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.titleTextAttributes = [.foregroundColor: foreground]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.rightBarButtonItem?.tintColor = foreground
    }

    // MARK: - Theme Menu

    private func configureThemeMenu() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "paintpalette"),
            menu: buildThemeMenu()
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "terminal.themeButton"
    }

    private func buildThemeMenu() -> UIMenu {
        let popular = buildSubmenu(
            title: "Popular",
            themes: [
                "Dracula", "Catppuccin Mocha", "Catppuccin Latte",
                "Nord", "Solarized Dark", "Solarized Light",
                "Gruvbox Dark", "Gruvbox Light", "Tokyo Night",
                "One Half Dark", "One Half Light", "Rose Pine",
                "Monokai Pro", "GitHub Dark", "GitHub Light",
            ]
        )

        let dark = UIMenu(
            title: "Dark",
            image: UIImage(systemName: "moon.fill"),
            children: alphabeticalSubmenus(
                themes: GhosttyThemeCatalog.allThemes.filter(\.isDark)
            )
        )

        let light = UIMenu(
            title: "Light",
            image: UIImage(systemName: "sun.max.fill"),
            children: alphabeticalSubmenus(
                themes: GhosttyThemeCatalog.allThemes.filter { !$0.isDark }
            )
        )

        return UIMenu(title: "Theme", children: [popular, dark, light])
    }

    private func buildSubmenu(
        title: String,
        themes names: [String]
    ) -> UIMenu {
        let actions = names.compactMap { name -> UIAction? in
            guard let theme = GhosttyThemeCatalog.theme(named: name) else {
                return nil
            }
            return themeAction(for: theme)
        }
        return UIMenu(
            title: title,
            image: UIImage(systemName: "star.fill"),
            children: actions
        )
    }

    private func alphabeticalSubmenus(
        themes: [GhosttyThemeDefinition]
    ) -> [UIMenu] {
        var grouped: [String: [GhosttyThemeDefinition]] = [:]
        for theme in themes {
            let letter = String(theme.name.prefix(1)).uppercased()
            let key = letter.first?.isLetter == true ? letter : "#"
            grouped[key, default: []].append(theme)
        }

        return grouped.sorted { $0.key < $1.key }.map { key, themes in
            UIMenu(
                title: key,
                children: themes.map { themeAction(for: $0) }
            )
        }
    }

    private func themeAction(for theme: GhosttyThemeDefinition) -> UIAction {
        UIAction(title: theme.name) { [weak self] _ in
            self?.applyTheme(theme)
        }
    }

    private func applyTheme(_ theme: GhosttyThemeDefinition) {
        saveTheme(theme)
        controller.setTheme(Self.savedTerminalTheme())
        applyBackgroundForCurrentAppearance()
    }
}

#if DEBUG
    private final class TerminalOutputAccessibilityView: UIView {
        private let session: InMemoryTerminalSession

        init(session: InMemoryTerminalSession) {
            self.session = session
            super.init(frame: .zero)
            isAccessibilityElement = true
            accessibilityIdentifier = "terminal.output"
            accessibilityLabel = "Terminal Output"
            isUserInteractionEnabled = false
            alpha = 0.01
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var accessibilityValue: String? {
            get { session.readViewportText() }
            set {}
        }
    }
#endif

// MARK: - Terminal Callbacks

extension ViewController:
    TerminalSurfaceTitleDelegate,
    TerminalSurfaceCloseDelegate,
    TerminalSurfaceTextSelectionRequestDelegate,
    UIAdaptivePresentationControllerDelegate
{
    func terminalDidChangeTitle(_ title: String) {
        self.title = title
    }

    func terminalDidClose(processAlive _: Bool) {
        ApplicationExitController.requestExit()
    }

    func terminalDidRequestTextSelection(_ request: TerminalTextSelectionRequest) {
        let selectionVC = TerminalSelectionViewController(
            text: request.text,
            anchorRange: request.anchorRange
        )
        selectionVC.onDone = { [weak self] in
            self?.terminalView.becomeFirstResponder()
        }
        let nav = UINavigationController(rootViewController: selectionVC)
        nav.modalPresentationStyle = .pageSheet
        nav.sheetPresentationController?.detents = [.medium(), .large()]
        nav.sheetPresentationController?.prefersGrabberVisible = true
        nav.presentationController?.delegate = self
        present(nav, animated: true)
    }

    /// Covers the user-gesture (grabber swipe) dismiss path only —
    /// programmatic dismiss does not trigger this callback, so the Done
    /// button restores focus via `onDone` instead.
    func presentationControllerDidDismiss(_: UIPresentationController) {
        terminalView.becomeFirstResponder()
    }
}

// MARK: - UIColor Hex

private extension UIColor {
    convenience init?(hexString: String) {
        let hex = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard hex.count == 6,
              let r = UInt8(hex.prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(4).prefix(2), radix: 16)
        else { return nil }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}
