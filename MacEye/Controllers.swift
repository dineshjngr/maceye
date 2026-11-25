import AppKit

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

/// The eyes in the menu bar.
final class StatusItemController {
    var menuProvider: (() -> NSMenu)?

    private var item: NSStatusItem?
    private var eyes: EyesView?

    func apply(_ config: Config) {
        guard config.showMenuBar && !config.eyesHidden else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            eyes = nil
            return
        }
        let blockHeight = 22 * CGFloat(config.menuBarSize)
        let eyeHeight = EyeLayout.eyeHeight(forTotalHeight: blockHeight, showBrow: config.showEyebrows)
        let width = EyeLayout.contentWidth(count: config.eyeCount, eyeHeight: eyeHeight,
                                           aspect: config.theme.aspect, spacing: config.spacing) + 10

        if item == nil {
            let new = NSStatusBar.system.statusItem(withLength: width)
            new.autosaveName = "MacEyeEyes"
            if let button = new.button {
                let view = EyesView(role: .menuBar)
                view.frame = button.bounds
                view.autoresizingMask = [.width, .height]
                view.onEyeClick = { [weak self, weak view] index in
                    if ConfigStore.shared.config.clickToBlink {
                        view?.blinkEye(at: index)
                    } else {
                        self?.showMenu()
                    }
                }
                view.onMenuRequest = { [weak self] _ in self?.showMenu() }
                button.addSubview(view)
                button.setAccessibilityLabel("MacEye")
                eyes = view
            }
            item = new
        }
        item?.length = width
        eyes?.contentHeight = blockHeight
    }

    private func showMenu() {
        guard let item, let menu = menuProvider?() else { return }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
}

/// The eyes that float on the desktop and can be dragged anywhere.
final class FloatingEyesController {
    var menuProvider: (() -> NSMenu)?

    private var panels: [String: NSPanel] = [:]
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.apply(ConfigStore.shared.config)
        }
    }

    private static func screenKey(_ screen: NSScreen) -> String {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return "screen-\(number?.intValue ?? 0)"
    }

    func apply(_ config: Config) {
        guard config.showFloating && !config.eyesHidden else {
            closeAll()
            return
        }
        let screens: [NSScreen]
        if config.floatingAllScreens {
            screens = NSScreen.screens
        } else {
            screens = NSScreen.screens.first.map { [$0] } ?? []
        }
        let wanted = Dictionary(uniqueKeysWithValues: screens.map { (Self.screenKey($0), $0) })

        for (key, panel) in panels where wanted[key] == nil {
            panel.orderOut(nil)
            panels[key] = nil
        }

        let eyeHeight = CGFloat(config.floatingSize)
        let pad = eyeHeight * 0.08 + 6
        let size = CGSize(
            width: EyeLayout.contentWidth(count: config.eyeCount, eyeHeight: eyeHeight,
                                          aspect: config.theme.aspect, spacing: config.spacing) + pad * 2,
            height: EyeLayout.totalHeight(eyeHeight: eyeHeight, showBrow: config.showEyebrows) + pad * 2)

        for (key, screen) in wanted {
            let panel = panels[key] ?? makePanel(key: key)
            panels[key] = panel
            (panel.contentView as? EyesView)?.padding = pad
            panel.level = config.floatingOnTop ? .floating : .normal

            var origin: CGPoint
            if let saved = config.floatingPositions[key], saved.count == 2 {
                origin = CGPoint(x: saved[0], y: saved[1])
            } else {
                let visible = screen.visibleFrame
                origin = CGPoint(x: visible.maxX - size.width - 40, y: visible.minY + 40)
            }
            // Keep the window reachable if a display was removed or resized.
            let onScreen = NSScreen.screens.contains { $0.frame.intersects(CGRect(origin: origin, size: size)) }
            if !onScreen {
                let visible = screen.visibleFrame
                origin = CGPoint(x: visible.maxX - size.width - 40, y: visible.minY + 40)
            }
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
            panel.orderFrontRegardless()
        }
    }

    func resetPositions() {
        ConfigStore.shared.config.floatingPositions = [:]
    }

    private func closeAll() {
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
    }

    private func makePanel(key: String) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = EyesView(role: .floating)
        view.isDraggable = true
        view.onEyeClick = { [weak view] index in
            if ConfigStore.shared.config.clickToBlink { view?.blinkEye(at: index) }
        }
        view.onMenuRequest = { [weak self, weak view] event in
            guard let view, let menu = self?.menuProvider?() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }
        view.onDragEnd = { [weak panel] in
            guard let panel else { return }
            let origin = panel.frame.origin
            ConfigStore.shared.config.floatingPositions[key] = [Double(origin.x), Double(origin.y)]
        }
        panel.contentView = view
        return panel
    }
}
