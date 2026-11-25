import AppKit
import Combine
import SwiftUI

@main
enum MacEyeMain {
    static func main() {
        if DebugTools.handleCommandLine() { return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ConfigStore.shared
    private let engine = EyeEngine.shared
    private let statusController = StatusItemController()
    private let floatingController = FloatingEyesController()
    private var settingsWindow: NSWindow?
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController.menuProvider = { [unowned self] in self.makeMenu() }
        floatingController.menuProvider = { [unowned self] in self.makeMenu() }
        HotKeyCenter.shared.handler = { [unowned self] action in self.perform(action) }

        engine.start()
        cancellable = store.$config.sink { [unowned self] config in
            self.statusController.apply(config)
            self.floatingController.apply(config)
            HotKeyCenter.shared.register(config.hotkeys)
            SettingsSync.shared.configChanged(config)
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didShowWelcome") {
            defaults.set(true, forKey: "didShowWelcome")
            showSettings()
        }
        if let folder = ProcessInfo.processInfo.environment["MACEYE_DUMP_DIR"] {
            DebugTools.startDumping(to: folder)
        }
    }

    /// Commands as links, for example `open maceye://blink`. Works from Shortcuts ("Open URL"),
    /// scripts and the terminal.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "maceye" {
            handleCommand(url)
        }
    }

    private func handleCommand(_ url: URL) {
        let command = (url.host ?? "").lowercased()
        let argument = url.pathComponents.dropFirst().first?.lowercased()

        func flag(_ current: Bool) -> Bool {
            switch argument {
            case "on": return true
            case "off": return false
            default: return !current
            }
        }

        switch command {
        case "blink":
            engine.blink(side: argument == "left" ? -1 : (argument == "right" ? 1 : nil))
        case "find":
            engine.findPointer()
        case "mood":
            if argument == "next" {
                engine.cycleMood()
            } else if let argument, let mood = Mood(rawValue: argument) {
                store.config.mood = mood
            }
        case "theme":
            if let argument, Theme.all.contains(where: { $0.id == argument }) {
                store.config.themeID = argument
            }
        case "floating":
            store.config.showFloating = flag(store.config.showFloating)
        case "menubar":
            store.config.showMenuBar = flag(store.config.showMenuBar)
        case "hide":
            store.config.eyesHidden = flag(store.config.eyesHidden)
        case "physics":
            store.config.googlyPhysics = flag(store.config.googlyPhysics)
        case "eyebrows":
            store.config.showEyebrows = flag(store.config.showEyebrows)
        case "settings":
            showSettings()
        default:
            break
        }
    }

    /// Opening the app again shows the settings. This is the way back if all eyes are hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .blink: engine.blink()
        case .toggleEyes: store.config.eyesHidden.toggle()
        case .cycleMood: engine.cycleMood()
        case .findPointer: engine.findPointer()
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 700),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "MacEye Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(store))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func makeMenu() -> NSMenu {
        let config = store.config
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let status = engine.statusLine {
            let item = NSMenuItem(title: status, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        menu.addItem(ActionMenuItem("Blink") { [unowned self] in self.engine.blink() })
        menu.addItem(ActionMenuItem("Find My Pointer") { [unowned self] in self.engine.findPointer() })

        let moodItem = NSMenuItem(title: "Mood", action: nil, keyEquivalent: "")
        let moodMenu = NSMenu()
        for mood in Mood.allCases {
            moodMenu.addItem(ActionMenuItem(mood.title, checked: config.mood == mood) { [unowned self] in
                self.store.config.mood = mood
            })
        }
        moodItem.submenu = moodMenu
        menu.addItem(moodItem)

        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        for theme in Theme.all {
            themeMenu.addItem(ActionMenuItem(theme.name, checked: config.themeID == theme.id) { [unowned self] in
                self.store.config.themeID = theme.id
            })
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Menu Bar Eyes", checked: config.showMenuBar) { [unowned self] in
            self.store.config.showMenuBar.toggle()
        })
        menu.addItem(ActionMenuItem("Floating Eyes", checked: config.showFloating) { [unowned self] in
            self.store.config.showFloating.toggle()
        })
        menu.addItem(ActionMenuItem("Googly Physics", checked: config.googlyPhysics) { [unowned self] in
            self.store.config.googlyPhysics.toggle()
        })

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Settings…") { [unowned self] in self.showSettings() })
        menu.addItem(ActionMenuItem("Quit MacEye") { NSApp.terminate(nil) })
        return menu
    }
}

/// Command-line helpers used to check the app without clicking through it.
enum DebugTools {
    /// Returns true if a debug command ran and the app should exit.
    static func handleCommandLine() -> Bool {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count {
            let ok = renderPreview(to: args[i + 1])
            print(ok ? "wrote \(args[i + 1])" : "failed to write preview")
            return true
        }
        if args.contains("--status") {
            printStatus()
            return true
        }
        return false
    }

    /// Writes the live state and a picture of every eyes view into a folder, every two seconds.
    /// Turned on by starting the app with the MACEYE_DUMP_DIR environment variable.
    static func startDumping(to folder: String) {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let timer = Timer(timeInterval: 2, repeats: true) { _ in dump(to: url) }
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func dump(to folder: URL) {
        let engine = EyeEngine.shared
        let s = engine.state
        var lines: [String] = []
        lines.append("time: \(Date())")
        lines.append("theme: \(s.config.themeID)  mood setting: \(s.config.mood.rawValue)  eyes: \(s.config.eyeCount)")
        lines.append("showMenuBar: \(s.config.showMenuBar)  showFloating: \(s.config.showFloating)  hidden: \(s.config.eyesHidden)")
        lines.append("googly: \(s.config.googlyPhysics)  eyebrows: \(s.config.showEyebrows)")
        lines.append(String(format: "pose: topLid=%.2f bottomLid=%.2f lidTilt=%.2f browTilt=%.2f pupilScale=%.2f",
                            s.pose.topLid, s.pose.bottomLid, s.pose.lidTilt, s.pose.browTilt, s.pupilScale))
        lines.append(String(format: "closure=%.2f redness=%.2f dizzy=%.2f blinkL=%.2f blinkR=%.2f rest=%@",
                            s.closure, s.redness, s.dizzy, s.blinkLeft, s.blinkRight, s.rest ? "yes" : "no"))
        lines.append(String(format: "target: %.0f, %.0f  pointer: %.0f, %.0f", s.target.x, s.target.y,
                            NSEvent.mouseLocation.x, NSEvent.mouseLocation.y))
        lines.append("status line: \(engine.statusLine ?? "none")")
        lines.append(String(format: "cpu load: %.0f%%  mic: %@  camera: %@", engine.system.cpuLoad * 100,
                            engine.privacy.micActive ? "in use" : "idle", engine.privacy.cameraActive ? "in use" : "idle"))

        var counts: [String: Int] = [:]
        for view in engine.allViews {
            let role = "\(view.role)"
            let index = counts[role, default: 0]
            counts[role] = index + 1
            let name = "\(role)-\(index)"
            let frame = view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) } ?? .zero
            lines.append("view \(name): visible=\(view.window?.isVisible ?? false) screen frame=\(frame)")
            guard view.bounds.width > 1, view.bounds.height > 1,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: folder.appendingPathComponent("\(name).png"))
            }
        }
        try? lines.joined(separator: "\n").write(to: folder.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
    }

    private static func printStatus() {
        let system = SystemMonitor()
        system.start()
        Thread.sleep(forTimeInterval: 1.0)
        print("microphone in use: \(PrivacyMonitor.microphoneInUse())")
        print("camera in use: \(PrivacyMonitor.cameraInUse())")
        print("battery percent: \(system.batteryPercent.map(String.init) ?? "no battery")")
        print("battery low: \(system.batteryLow)")
        print("accessibility trusted: \(FocusTracker.isTrusted)")
        let keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        print(String(format: "seconds since last key press: %.1f", keyIdle))
        if let any = CGEventType(rawValue: ~0) {
            let anyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
            print(String(format: "seconds since any input: %.1f", anyIdle))
        }
        let hotkeys = Config().hotkeys.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.display)" }
        print("default shortcuts: \(hotkeys.joined(separator: ", "))")
        if let data = Config().encoded(), let round = Config.decode(data) {
            print("settings round trip ok: \(round == Config())")
        } else {
            print("settings round trip ok: false")
        }
        let partial = Data(#"{"themeID":"cat","eyeCount":4}"#.utf8)
        if let merged = Config.decode(partial) {
            print("partial settings load: theme=\(merged.themeID) eyes=\(merged.eyeCount) blink=\(merged.randomBlink)")
        } else {
            print("partial settings load: failed")
        }
    }

    /// Draws every theme in every mood into one PNG.
    private static func renderPreview(to path: String) -> Bool {
        let moods: [Mood] = [.neutral, .happy, .angry, .sad, .sleepy, .surprised, .suspicious]
        let extras = ["blink", "dizzy", "tired", "closed", "googly gaze"]
        let columns = moods.count + extras.count
        let cell = CGSize(width: 170, height: 118)
        let labelHeight: CGFloat = 20
        let size = CGSize(width: cell.width * CGFloat(columns), height: (cell.height + labelHeight) * CGFloat(Theme.all.count))
        let scale: CGFloat = 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(srgbRed: 0.90, green: 0.91, blue: 0.93, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.black,
        ]

        for (row, theme) in Theme.all.enumerated() {
            let y = size.height - CGFloat(row + 1) * (cell.height + labelHeight)
            for column in 0..<columns {
                let x = CGFloat(column) * cell.width
                var pose = EyePose()
                var closure = 0.0
                var redness = 0.0
                var dizzy = 0.0
                var gaze = CGPoint(x: 0.35, y: 0.2)
                let label: String
                if column < moods.count {
                    pose = .forMood(moods[column])
                    label = "\(theme.name) · \(moods[column].title)"
                } else {
                    let extra = extras[column - moods.count]
                    label = "\(theme.name) · \(extra)"
                    switch extra {
                    case "blink": closure = 0.6
                    case "dizzy": dizzy = 1
                    case "tired":
                        pose = EyePose(topLid: 0.40, bottomLid: 0.08, lidTilt: 0.15, browTilt: 0.3, browRaise: -0.3)
                        redness = 0.9
                    case "closed": closure = 1
                    default: gaze = CGPoint(x: -0.7, y: -0.7)
                    }
                }
                let area = CGRect(x: x, y: y + labelHeight, width: cell.width, height: cell.height).insetBy(dx: 14, dy: 12)
                let rects = EyeLayout.rects(count: 2, in: area, aspect: theme.aspect, spacing: 0.12, showBrow: true)
                for (i, rect) in rects.enumerated() {
                    let visual = EyeVisual.make(side: EyeLayout.side(index: i, count: 2), gaze: gaze, expression: pose,
                                                closure: closure, moodLids: true, redness: redness,
                                                dizzy: dizzy, dizzyPhase: 0.6)
                    EyeRenderer.draw(visual, theme: theme, in: rect, ctx: ctx, showBrow: true)
                }
                (label as NSString).draw(at: CGPoint(x: x + 8, y: y + 4), withAttributes: attributes)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let image = ctx.makeImage() else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }
}
