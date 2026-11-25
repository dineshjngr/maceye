import CoreGraphics
import Foundation
import QuartzCore

/// The Core Animation layers of one eye.
///
/// Live eyes are built from layers instead of being redrawn every frame. Moving a pupil is then
/// only a layer position change, which costs almost nothing. Redrawing a menu bar item every
/// frame is expensive, because macOS snapshots the whole item again for every display.
final class EyeLayers {
    let root = CALayer()
    private let sclera = CAShapeLayer()
    private let inner = CALayer()
    private let innerMask = CAShapeLayer()
    private let veins = CAShapeLayer()
    private let glow = CAGradientLayer()
    private let iris = CAShapeLayer()
    private let pupil = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let spiral = CAShapeLayer()
    private let topLid = CAShapeLayer()
    private let bottomLid = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let brow = CAShapeLayer()

    private var theme = Theme.classic
    private var size = CGSize.zero
    private var body = CGRect.zero
    private var lineWidth: CGFloat = 1
    private var irisRadius: CGFloat = 0
    private var pupilRadius: CGFloat = 0
    private var showVeins = false
    private var last: EyeVisual?

    init() {
        root.addSublayer(sclera)
        root.addSublayer(inner)
        for layer in [veins, glow, iris, pupil, highlight, spiral, topLid, bottomLid] as [CALayer] {
            inner.addSublayer(layer)
        }
        inner.mask = innerMask
        root.addSublayer(outline)
        root.addSublayer(brow)
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        spiral.isHidden = true
    }

    private var allLayers: [CALayer] {
        [root, sclera, inner, innerMask, veins, glow, iris, pupil, highlight, spiral, topLid, bottomLid, outline, brow]
    }

    func configure(rect: CGRect, theme: Theme, showBrow: Bool, scale: CGFloat) {
        self.theme = theme
        size = rect.size
        last = nil
        for layer in allLayers { layer.contentsScale = scale }

        root.frame = rect
        let local = CGRect(origin: .zero, size: rect.size)
        lineWidth = max(0.75, rect.height * 0.045)
        body = local.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let ry = body.height / 2
        let ellipse = CGPath(ellipseIn: body, transform: nil)

        sclera.frame = local
        sclera.path = ellipse
        sclera.fillColor = theme.sclera.cg

        inner.frame = local
        innerMask.frame = local
        innerMask.path = ellipse
        innerMask.fillColor = CGColor(gray: 0, alpha: 1)

        showVeins = rect.height >= 28
        veins.frame = local
        veins.path = veinsPath()
        veins.fillColor = nil
        veins.strokeColor = RGBA(0.85, 0.12, 0.12).cg
        veins.lineWidth = max(0.6, lineWidth * 0.45)
        veins.lineCap = .round
        veins.opacity = 0

        irisRadius = CGFloat(theme.irisRatio) * ry
        iris.isHidden = irisRadius <= 0
        if irisRadius > 0 {
            let inset = lineWidth * 0.35
            let r = irisRadius - inset
            iris.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
            iris.fillColor = theme.iris.cg
            iris.strokeColor = theme.iris.darker(0.4).cg
            iris.lineWidth = lineWidth * 0.7
        }

        pupil.fillColor = theme.pupil.cg
        highlight.fillColor = theme.highlight.cg
        var halo = theme.pupil
        halo.a = 0.55
        var clear = theme.pupil
        clear.a = 0
        glow.colors = [halo.cg, halo.cg, clear.cg]
        glow.locations = [0, 0.26, 1]
        glow.isHidden = !theme.glow

        spiral.fillColor = nil
        spiral.strokeColor = theme.pupil.cg
        spiral.lineCap = .round
        spiral.lineJoin = .round

        for lid in [topLid, bottomLid] {
            lid.frame = local
            lid.fillColor = theme.lid.cg
            lid.strokeColor = theme.outline.cg
            lid.lineWidth = lineWidth * 0.8
            lid.path = nil
        }

        outline.frame = local
        outline.path = ellipse
        outline.fillColor = nil
        outline.strokeColor = theme.outline.cg
        outline.lineWidth = lineWidth

        brow.isHidden = !showBrow
        let half = body.width / 2 * 0.95
        let browPath = CGMutablePath()
        browPath.move(to: CGPoint(x: -half, y: 0))
        browPath.addQuadCurve(to: CGPoint(x: half, y: 0), control: CGPoint(x: 0, y: rect.height * 0.1))
        brow.path = browPath
        brow.fillColor = nil
        brow.strokeColor = theme.brow.cg
        brow.lineWidth = max(1.2, rect.height * 0.105)
        brow.lineCap = .round
    }

    private func veinsPath() -> CGPath {
        let path = CGMutablePath()
        let rx = body.width / 2
        let ry = body.height / 2
        for k in 0..<7 {
            let a = CGFloat(k) * 0.9 + 0.35
            path.move(to: CGPoint(x: body.midX + cos(a) * rx, y: body.midY + sin(a) * ry))
            path.addLine(to: CGPoint(x: body.midX + cos(a + 0.22) * rx * 0.74, y: body.midY + sin(a + 0.22) * ry * 0.74))
            path.addLine(to: CGPoint(x: body.midX + cos(a - 0.1) * rx * 0.52, y: body.midY + sin(a - 0.1) * ry * 0.52))
        }
        return path
    }

    private func rebuildPupil(scale: Double) {
        let ry = body.height / 2
        var r = CGFloat(theme.pupilRatio * scale) * ry
        if irisRadius > 0 { r = min(r, irisRadius * 0.86) }
        pupilRadius = r

        switch theme.pupilShape {
        case .round:
            pupil.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
        case .slit:
            let halfH = irisRadius > 0 ? irisRadius * 0.92 : r * 1.5
            let halfW = r * 0.42
            pupil.path = CGPath(ellipseIn: CGRect(x: -halfW, y: -halfH, width: halfW * 2, height: halfH * 2), transform: nil)
        case .square:
            let s = r * 1.7
            pupil.path = CGPath(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s),
                                cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
        }

        let hr = r * 0.27
        highlight.path = CGPath(ellipseIn: CGRect(x: -r * 0.34 - hr, y: r * 0.36 - hr, width: hr * 2, height: hr * 2), transform: nil)

        let glowRadius = r * 2.3
        glow.bounds = CGRect(x: 0, y: 0, width: glowRadius * 2, height: glowRadius * 2)

        let spiralRadius = max(max(irisRadius, r), ry * 0.5) * 0.95
        let spiralPath = CGMutablePath()
        let steps = 72
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = t * 2.6 * 2 * Double.pi
            let point = CGPoint(x: CGFloat(cos(a)) * spiralRadius * CGFloat(t), y: CGFloat(sin(a)) * spiralRadius * CGFloat(t))
            if i == 0 { spiralPath.move(to: point) } else { spiralPath.addLine(to: point) }
        }
        spiral.path = spiralPath
        spiral.lineWidth = max(1, spiralRadius * 0.17)
    }

    /// Call inside a CATransaction with actions disabled.
    func apply(_ v: EyeVisual) {
        let old = last
        last = v
        let rx = body.width / 2
        let ry = body.height / 2

        if old == nil || abs(old!.pupilScale - v.pupilScale) > 0.003 {
            rebuildPupil(scale: v.pupilScale)
        }

        let discRadius = max(irisRadius, pupilRadius)
        let travelX = max(0, rx - discRadius * 0.92)
        let travelY = max(0, ry - discRadius * 0.92)
        let center = CGPoint(x: body.midX + v.gaze.x * travelX, y: body.midY + v.gaze.y * travelY)
        iris.position = center
        pupil.position = center
        highlight.position = center
        spiral.position = center
        glow.position = center

        let dizzy = v.dizzy > 0.5
        pupil.isHidden = dizzy
        highlight.isHidden = dizzy || theme.highlight.a <= 0.01 || pupilRadius < 2.2
        glow.isHidden = dizzy || !theme.glow
        spiral.isHidden = !dizzy
        if dizzy {
            spiral.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(v.dizzyPhase)))
        }

        if old == nil || abs(old!.redness - v.redness) > 0.002 {
            sclera.fillColor = theme.sclera.mixed(with: RGBA(1.0, 0.40, 0.38), v.redness * 0.5).cg
            veins.opacity = (showVeins && v.redness > 0.25) ? Float(min(0.75, v.redness * 0.75)) : 0
        }

        let margin = lineWidth * 2 + 2
        let lidSlope = CGFloat(-v.side * v.lidTilt)

        if old == nil || abs(old!.topLid - v.topLid) > 0.0005 || abs(old!.lidTilt - v.lidTilt) > 0.0005 {
            if v.topLid > 0.004 {
                let y = body.maxY - CGFloat(v.topLid) * body.height
                let k = ry * 0.5 * lidSlope
                let arch = ry * 0.55 * CGFloat(1 - v.topLid)
                let left = CGPoint(x: body.minX - margin, y: y + k)
                let right = CGPoint(x: body.maxX + margin, y: y - k)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: body.minX - margin, y: body.maxY + margin))
                path.addLine(to: CGPoint(x: body.maxX + margin, y: body.maxY + margin))
                path.addLine(to: right)
                path.addQuadCurve(to: left, control: CGPoint(x: body.midX, y: y + arch))
                path.closeSubpath()
                topLid.path = path
            } else {
                topLid.path = nil
            }
        }

        if old == nil || abs(old!.bottomLid - v.bottomLid) > 0.0005 || abs(old!.bottomArch - v.bottomArch) > 0.0005 {
            if v.bottomLid > 0.004 {
                let y = body.minY + CGFloat(v.bottomLid) * body.height
                let arch = ry * 0.6 * CGFloat(v.bottomArch) * CGFloat(1 - v.bottomLid)
                let left = CGPoint(x: body.minX - margin, y: y)
                let right = CGPoint(x: body.maxX + margin, y: y)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: body.minX - margin, y: body.minY - margin))
                path.addLine(to: CGPoint(x: body.maxX + margin, y: body.minY - margin))
                path.addLine(to: right)
                path.addQuadCurve(to: left, control: CGPoint(x: body.midX, y: y + arch))
                path.closeSubpath()
                bottomLid.path = path
            } else {
                bottomLid.path = nil
            }
        }

        if !brow.isHidden {
            let browSlope = CGFloat(-v.side * v.browTilt)
            brow.position = CGPoint(x: body.midX, y: size.height + size.height * CGFloat(0.13 + 0.07 * v.browRaise))
            brow.setAffineTransform(CGAffineTransform(rotationAngle: -browSlope * 0.42))
        }
    }
}
