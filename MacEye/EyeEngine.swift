import AppKit
import Combine
import UserNotifications

/// One frame of shared state. Every eyes view draws from this.
struct EngineState {
    var config = Config()
    var theme = Theme.classic
    /// Screen point the eyes look at (AppKit coordinates, y up).
    var target = CGPoint.zero
    /// Pupils go all the way to the edge (used by Find My Pointer).
    var saturate = false
    /// Eyes ignore the target and rest (asleep or closed).
    var rest = false
    var pose = EyePose()
    var blinkLeft = 0.0
    var blinkRight = 0.0
    /// 0 = open, 1 = shut (sleep, or microphone/camera in use).
    var closure = 0.0
    var redness = 0.0
    var dizzy = 0.0
    var dizzyPhase = 0.0
    var pupilScale = 1.0
}

/// Runs the animation: follows the pointer, blinks, sleeps and picks the mood.
final class EyeEngine {
    static let shared = EyeEngine()

    private(set) var state = EngineState()
    private(set) var statusLine: String?

    let system = SystemMonitor()
    let privacy = PrivacyMonitor()
    let focus = FocusTracker()
    private let spotlight = PointerSpotlight()

    private let views = NSHashTable<EyesView>.weakObjects()
    private var timer: Timer?
    private var fastRate = true
    private var quietTime = 0.0
    private var cancellable: AnyCancellable?

    private var lastTick = CACurrentMediaTime()
    private var lastPoll = 0.0
    private var lastMouse = NSEvent.mouseLocation
    private var speed = 0.0
    private var lastDirection = 0
    private var reversals: [Double] = []
    private var dizzyUntil = 0.0
    private var wideUntil = 0.0
    private var findUntil = 0.0

    private var keyIdle = 999.0
    private var anyIdle = 0.0
    private var isDark = false

    private var blinkStartLeft = -10.0
    private var blinkStartRight = -10.0
    private var nextBlink = CACurrentMediaTime() + 3
    private let blinkDuration = 0.22

    private var lastBreak = CACurrentMediaTime()
    private var breakNotified = false

    /// Set by the MACEYE_SIM environment variable ("orbit" or "shake"). Only for testing.
    private let simulation = ProcessInfo.processInfo.environment["MACEYE_SIM"]

    private init() {}

    func start() {
        guard timer == nil else { return }
        cancellable = ConfigStore.shared.$config.sink { [weak self] new in
            self?.configChanged(new)
        }
        system.start()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lastBreak = CACurrentMediaTime()
            self?.breakNotified = false
        }
        schedule(fast: true)
    }

    func register(_ view: EyesView) {
        views.add(view)
    }

    var allViews: [EyesView] { views.allObjects }

    private func configChanged(_ new: Config) {
        let old = state.config
        state.config = new
        state.theme = new.theme
        if new.privacyClose { privacy.start() } else { privacy.stop() }
        if new.breakReminder && !old.breakReminder {
            lastBreak = CACurrentMediaTime()
            breakNotified = false
        }
        if new.breakReminder && new.breakNotification && !(old.breakReminder && old.breakNotification) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        wake()
    }

    // MARK: Actions

    /// side: -1 left eye, +1 right eye, nil both.
    func blink(side: Int? = nil) {
        let now = CACurrentMediaTime()
        if side == nil || side == -1 { blinkStartLeft = now }
        if side == nil || side == 1 { blinkStartRight = now }
        wake()
    }

    func findPointer() {
        findUntil = CACurrentMediaTime() + 1.8
        spotlight.show(duration: 1.8)
        wake()
    }

    func cycleMood() {
        let all = Mood.allCases
        let current = ConfigStore.shared.config.mood
        let index = all.firstIndex(of: current) ?? 0
        ConfigStore.shared.config.mood = all[(index + 1) % all.count]
    }

    // MARK: Timer

    private func schedule(fast: Bool) {
        timer?.invalidate()
        fastRate = fast
        let t = Timer(timeInterval: fast ? 1.0 / 60.0 : 1.0 / 8.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = fast ? 0.002 : 0.03
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func wake() {
        quietTime = 0
        if !fastRate && timer != nil { schedule(fast: true) }
    }

    // MARK: Frame

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0.001), 0.1)
        lastTick = now
        let cfg = state.config

        // Pointer movement.
        var mouse = NSEvent.mouseLocation
        if let simulation, let frame = NSScreen.screens.first?.frame {
            // Test mode: a pretend pointer, so the eyes can be checked without touching the real one.
            switch simulation {
            case "shake":
                mouse = CGPoint(x: frame.midX + 150 * sin(now * 2 * Double.pi * 4), y: frame.midY)
            default:
                mouse = CGPoint(x: frame.midX + 320 * cos(now * 2), y: frame.midY + 320 * sin(now * 2))
            }
        }
        let dx = mouse.x - lastMouse.x
        let dy = mouse.y - lastMouse.y
        let moved = abs(dx) + abs(dy) > 0.01
        lastMouse = mouse
        let instantSpeed = hypot(dx, dy) / dt
        speed += (instantSpeed - speed) * min(1, dt * 12)

        if cfg.reactShake {
            if abs(dx) > 2 && instantSpeed > 500 {
                let direction = dx > 0 ? 1 : -1
                if lastDirection != 0 && direction != lastDirection { reversals.append(now) }
                lastDirection = direction
            }
            reversals.removeAll { now - $0 > 0.9 }
            if reversals.count >= 5 {
                dizzyUntil = now + 2.2
                reversals.removeAll()
            }
        }
        if cfg.reactFastMouse && speed > 3200 {
            wideUntil = now + 0.5
        }

        // Slow checks, four times a second.
        if now - lastPoll > 0.25 {
            lastPoll = now
            keyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
            if let any = CGEventType(rawValue: ~0) {
                anyIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
            }
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            if cfg.followTextCursor && keyIdle < 2 { focus.refresh() }
        }

        let typing = keyIdle < 1.5
        let asleep = cfg.sleepWhenIdle && anyIdle > cfg.idleMinutes * 60
        let privacyActive = cfg.privacyClose && privacy.active
        let finding = now < findUntil
        let dizzyNow = now < dizzyUntil
        let wide = now < wideUntil

        // Eye break: 20 seconds without input counts as a break.
        if anyIdle >= 20 {
            lastBreak = now
            breakNotified = false
        }
        let breakDue = cfg.breakReminder && now - lastBreak >= cfg.breakMinutes * 60
        if breakDue && !breakNotified {
            breakNotified = true
            if cfg.breakNotification { sendBreakNotification() }
        }
        let cpuHot = cfg.cpuTired && system.cpuHigh
        let batteryLow = cfg.batteryTired && system.batteryLow

        // Pick the pose.
        var targetPose: EyePose
        var targetRed = 0.0
        if cfg.mood == .auto {
            targetPose = EyePose.forMood(state.theme.baseMood)
            if finding || wide {
                targetPose = .forMood(.surprised)
            } else if breakDue {
                targetPose = EyePose(topLid: 0.46, bottomLid: 0.04, lidTilt: -0.55, browTilt: -0.8, browRaise: 0)
            } else if cpuHot {
                targetPose = EyePose(topLid: 0.40, bottomLid: 0.08, lidTilt: 0.15, browTilt: 0.3, browRaise: -0.3)
            } else if batteryLow {
                targetPose = .forMood(.sleepy)
            } else if cfg.reactTyping && typing {
                targetPose = .focused
            }
        } else {
            targetPose = finding ? .forMood(.surprised) : .forMood(cfg.mood)
        }
        if breakDue { targetRed = 0.55 }
        if cpuHot { targetRed = 0.9 }

        let k = 1 - exp(-dt * 12)
        state.pose.approach(targetPose, k)
        state.redness += (targetRed - state.redness) * (1 - exp(-dt * 3))

        // Closing for sleep or privacy.
        let closeTarget = (privacyActive || asleep) ? 1.0 : 0.0
        let closeRate = privacyActive ? 9.0 : (closeTarget > 0 ? 1.6 : 10.0)
        state.closure += (closeTarget - state.closure) * (1 - exp(-dt * closeRate))
        if abs(state.closure - closeTarget) < 0.002 { state.closure = closeTarget }
        state.rest = state.closure > 0.6

        // Blinking.
        if cfg.randomBlink && !asleep && !privacyActive && now >= nextBlink {
            blinkStartLeft = now
            blinkStartRight = now
            nextBlink = now + (Double.random(in: 0...1) < 0.15 ? 0.32 : Double.random(in: 2.5...7.5))
        }
        state.blinkLeft = blinkValue(start: blinkStartLeft, now: now)
        state.blinkRight = blinkValue(start: blinkStartRight, now: now)

        // Dizzy spiral.
        state.dizzy += ((dizzyNow ? 1.0 : 0.0) - state.dizzy) * (1 - exp(-dt * 14))
        if state.dizzy > 0.01 { state.dizzyPhase -= dt * 13 }

        var pupil = 1.0
        if cfg.adaptivePupil { pupil *= isDark ? 1.16 : 0.9 }
        if finding { pupil *= 1.2 }
        state.pupilScale += (pupil - state.pupilScale) * k

        // Where to look.
        var lookAt = mouse
        if cfg.followTextCursor && keyIdle < 2, let point = focus.point, now - focus.updatedAt < 1.5 {
            lookAt = point
        }
        state.target = lookAt
        state.saturate = finding

        // Status text for the menu.
        if privacyActive {
            statusLine = privacy.cameraActive ? "Camera in use — eyes closed" : "Microphone in use — eyes closed"
        } else if asleep {
            statusLine = "Sleeping"
        } else if breakDue {
            statusLine = "Time for an eye break: look far away for 20 seconds"
        } else if cpuHot {
            statusLine = "CPU is busy (\(Int(system.cpuLoad * 100))%)"
        } else if batteryLow {
            statusLine = "Battery is low"
        } else {
            statusLine = nil
        }

        // Step and redraw the views.
        var anyChanged = false
        for view in views.allObjects {
            if view.step(dt: dt, state: state) { anyChanged = true }
        }

        // Drop to a slow rate when nothing is moving, to save energy.
        let animating = moved || anyChanged || dizzyNow || finding
            || state.blinkLeft > 0 || state.blinkRight > 0
            || state.pose.distance(to: targetPose) > 0.003
            || abs(state.closure - closeTarget) > 0.002
        if animating {
            quietTime = 0
            if !fastRate { schedule(fast: true) }
        } else {
            quietTime += dt
            if fastRate && quietTime > 1.0 { schedule(fast: false) }
        }
    }

    private func blinkValue(start: Double, now: Double) -> Double {
        let t = (now - start) / blinkDuration
        guard t >= 0, t <= 1 else { return 0 }
        return sin(t * Double.pi)
    }

    private func sendBreakNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Time for an eye break"
        content.body = "Look at something far away for 20 seconds."
        let request = UNNotificationRequest(identifier: "maceye.break", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Rings that pulse around the pointer so it is easy to find.
final class PointerSpotlight {
    private var window: NSPanel?
    private var timer: Timer?
    private let size: CGFloat = 280

    func show(duration: Double) {
        let panel = window ?? makeWindow()
        window = panel
        guard let layer = panel.contentView?.layer else { return }
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let start = CACurrentMediaTime()
        for i in 0..<3 {
            let ring = CAShapeLayer()
            ring.frame = bounds
            ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 14, dy: 14), transform: nil)
            ring.fillColor = nil
            ring.strokeColor = NSColor.systemYellow.cgColor
            ring.lineWidth = 9
            ring.opacity = 0
            layer.addSublayer(ring)

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.08
            scale.toValue = 1.0
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            fade.keyTimes = [0, 0.25, 1]
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 0.9
            group.beginTime = start + Double(i) * 0.38
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(group, forKey: "pulse")
        }
        follow(panel)
        panel.orderFrontRegardless()

        timer?.invalidate()
        let end = start + duration
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            if CACurrentMediaTime() >= end {
                timer.invalidate()
                self.window?.orderOut(nil)
            } else if let panel = self.window {
                self.follow(panel)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func follow(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(CGPoint(x: mouse.x - size / 2, y: mouse.y - size / 2))
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        panel.contentView = view
        return panel
    }
}
