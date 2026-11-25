import AppKit
import SwiftUI

/// Shows a row of eyes. Used in the menu bar, in the floating window and in the settings preview.
final class EyesView: NSView {
    enum Role {
        case menuBar
        case floating
        case preview
    }

    let role: Role
    /// Menu bar only: height of the eyes block, centred in the view.
    var contentHeight: CGFloat?
    var padding: CGFloat = 0
    var isDraggable = false

    /// Called with the index of the clicked eye.
    var onEyeClick: ((Int) -> Void)?
    var onMenuRequest: ((NSEvent) -> Void)?
    var onDragEnd: (() -> Void)?

    private struct Signature: Equatable {
        var rects: [CGRect]
        var theme: Theme
        var showBrow: Bool
        var scale: CGFloat
    }

    private var eyes: [EyeLayers] = []
    private var signature: Signature?
    private var positions: [CGPoint] = []
    private var velocities: [CGPoint] = []
    private var applied: [EyeVisual] = []
    private var darkBar = false

    /// Other displays show a snapshot of the menu bar item. It is refreshed a few times a second.
    private var mirrorDirty = false
    private var lastMirrorRefresh = 0.0

    private var pressActive = false
    private var didDrag = false
    private var dragStartMouse = CGPoint.zero
    private var dragStartOrigin = CGPoint.zero

    init(role: Role) {
        self.role = role
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        EyeEngine.shared.register(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDarkBar()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateDarkBar()
    }

    private func updateDarkBar() {
        darkBar = role == .menuBar && effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        signature = nil
    }

    private func eyeRects(_ s: EngineState) -> [CGRect] {
        var area = bounds.insetBy(dx: padding, dy: padding)
        if let h = contentHeight {
            area = CGRect(x: bounds.minX + 2, y: bounds.midY - h / 2, width: max(0, bounds.width - 4), height: h)
        }
        return EyeLayout.rects(count: s.config.eyeCount, in: area, aspect: s.theme.aspect,
                               spacing: s.config.spacing, showBrow: s.config.showEyebrows)
    }

    private func displayTheme(_ s: EngineState) -> Theme {
        var theme = s.theme
        if darkBar {
            // Dark eyebrows and outlines disappear on a dark menu bar.
            let light = RGBA(0.93, 0.93, 0.95)
            if theme.brow.luminance < 0.4 { theme.brow = light }
            if theme.outline.luminance < 0.4 && theme.sclera.luminance < 0.4 { theme.outline = light }
        }
        return theme
    }

    /// Gives the pupils a push. Only visible with googly physics on.
    func poke(_ impulse: CGPoint) {
        for i in velocities.indices {
            velocities[i].x += impulse.x
            velocities[i].y += impulse.y
        }
    }

    /// Advances the eyes by one frame. Returns true if the picture changed.
    func step(dt: Double, state s: EngineState) -> Bool {
        guard let window, window.isVisible, let host = layer else { return false }
        let rects = eyeRects(s)
        let count = rects.count
        let newSignature = Signature(rects: rects, theme: displayTheme(s), showBrow: s.config.showEyebrows,
                                     scale: window.backingScaleFactor)
        let rebuilt = newSignature != signature

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if rebuilt {
            signature = newSignature
            while eyes.count > count { eyes.removeLast().root.removeFromSuperlayer() }
            while eyes.count < count {
                let eye = EyeLayers()
                host.addSublayer(eye.root)
                eyes.append(eye)
            }
            for (i, rect) in rects.enumerated() {
                eyes[i].configure(rect: rect, theme: newSignature.theme, showBrow: newSignature.showBrow, scale: newSignature.scale)
            }
            applied = []
        }
        if positions.count != count {
            positions = Array(repeating: .zero, count: count)
            velocities = Array(repeating: .zero, count: count)
        }

        var visuals: [EyeVisual] = []
        visuals.reserveCapacity(count)
        for (i, rect) in rects.enumerated() {
            var desired = CGPoint.zero
            if s.rest {
                desired = CGPoint(x: 0, y: -0.4)
            } else if s.dizzy < 0.5 {
                let local = CGPoint(x: rect.midX, y: rect.midY)
                let center = window.convertPoint(toScreen: convert(local, to: nil))
                let dx = s.target.x - center.x
                let dy = s.target.y - center.y
                let distance = hypot(dx, dy)
                if distance > 0.5 {
                    let falloff = max(rect.height * 2, 50)
                    let amount = s.saturate ? 1 : min(1, distance / falloff)
                    desired = CGPoint(x: dx / distance * amount, y: dy / distance * amount)
                }
            }

            var p = positions[i]
            var v = velocities[i]
            if s.config.googlyPhysics {
                // A loose spring: the pupil overshoots and wobbles, and bounces off the edge.
                let steps = max(1, Int((dt / 0.008).rounded(.up)))
                let h = dt / Double(steps)
                for _ in 0..<steps {
                    let ax = 170 * (desired.x - p.x) - 6.5 * v.x
                    let ay = 170 * (desired.y - p.y) - 6.5 * v.y
                    v.x += ax * h
                    v.y += ay * h
                    p.x += v.x * h
                    p.y += v.y * h
                    let length = hypot(p.x, p.y)
                    if length > 1 {
                        let nx = p.x / length
                        let ny = p.y / length
                        p = CGPoint(x: nx, y: ny)
                        let outward = v.x * nx + v.y * ny
                        if outward > 0 {
                            v.x -= 1.6 * outward * nx
                            v.y -= 1.6 * outward * ny
                        }
                    }
                }
            } else {
                let k = 1 - exp(-dt * 20)
                p.x += (desired.x - p.x) * k
                p.y += (desired.y - p.y) * k
                v = .zero
            }
            positions[i] = p
            velocities[i] = v

            let side = EyeLayout.side(index: i, count: count)
            let blink = side < 0 ? s.blinkLeft : (side > 0 ? s.blinkRight : max(s.blinkLeft, s.blinkRight))
            visuals.append(EyeVisual.make(side: side, gaze: p, expression: s.pose,
                                          closure: max(blink, s.closure), moodLids: s.config.showEyelids,
                                          pupilScale: s.pupilScale, redness: s.redness,
                                          dizzy: s.dizzy, dizzyPhase: s.dizzyPhase))
        }

        var changed = rebuilt || applied.count != count
        if !changed {
            for i in visuals.indices where !visuals[i].isClose(to: applied[i], tolerance: 0.002) {
                changed = true
                break
            }
        }
        if changed {
            for i in visuals.indices { eyes[i].apply(visuals[i]) }
            applied = visuals
            mirrorDirty = true
        }

        if role == .menuBar && mirrorDirty && NSScreen.screens.count > 1 {
            let now = CACurrentMediaTime()
            if now - lastMirrorRefresh > 0.4 {
                lastMirrorRefresh = now
                mirrorDirty = false
                superview?.needsDisplay = true
            }
        }
        return changed
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            pressActive = false
            onMenuRequest?(event)
            return
        }
        pressActive = true
        didDrag = false
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressActive, isDraggable, let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y
        if !didDrag && hypot(dx, dy) < 3 { return }
        didDrag = true
        let old = window.frame.origin
        let new = CGPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy)
        window.setFrameOrigin(new)
        poke(CGPoint(x: -(new.x - old.x) * 0.07, y: -(new.y - old.y) * 0.07))
    }

    override func mouseUp(with event: NSEvent) {
        guard pressActive else { return }
        pressActive = false
        if didDrag {
            didDrag = false
            onDragEnd?()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let rects = eyeRects(EyeEngine.shared.state)
        guard !rects.isEmpty else { return }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, rect) in rects.enumerated() {
            let d = abs(rect.midX - point.x)
            if d < bestDistance {
                bestDistance = d
                best = i
            }
        }
        onEyeClick?(best)
    }

    override func rightMouseDown(with event: NSEvent) {
        onMenuRequest?(event)
    }

    /// Shared click behaviour: blink the clicked eye and wobble it.
    func blinkEye(at index: Int) {
        let count = max(1, EyeEngine.shared.state.config.eyeCount)
        let side = EyeLayout.side(index: index, count: count)
        EyeEngine.shared.blink(side: side < 0 ? -1 : (side > 0 ? 1 : nil))
        let angle = Double.random(in: 0..<(2 * Double.pi))
        poke(CGPoint(x: cos(angle) * 7, y: sin(angle) * 7))
    }
}

/// Live eyes inside the settings window.
struct EyesPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> EyesView {
        let view = EyesView(role: .preview)
        view.padding = 12
        view.onEyeClick = { [weak view] index in view?.blinkEye(at: index) }
        return view
    }

    func updateNSView(_ view: EyesView, context: Context) {}
}
