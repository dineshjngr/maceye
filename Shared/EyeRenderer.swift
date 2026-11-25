import CoreGraphics
import Foundation

/// Everything needed to draw one eye for one frame.
struct EyeVisual: Equatable {
    /// -1 = left eye, +1 = right eye, 0 = a single centred eye.
    var side = 0.0
    /// Pupil position inside the unit disc. y is up.
    var gaze = CGPoint.zero
    var topLid = 0.0
    var bottomLid = 0.0
    var lidTilt = 0.0
    var bottomArch = -0.3
    var browTilt = 0.0
    var browRaise = 0.0
    var pupilScale = 1.0
    var redness = 0.0
    var dizzy = 0.0
    var dizzyPhase = 0.0

    /// Combines a mood pose with a blink or sleep closure (0 = open, 1 = shut).
    static func make(side: Double, gaze: CGPoint, expression e: EyePose, closure: Double,
                     moodLids: Bool, pupilScale: Double = 1, redness: Double = 0,
                     dizzy: Double = 0, dizzyPhase: Double = 0) -> EyeVisual {
        var v = EyeVisual()
        v.side = side
        v.gaze = gaze
        let close = min(1, max(0, closure))
        var top = moodLids ? e.topLid : 0
        var bottom = moodLids ? e.bottomLid : 0
        let open = max(0, 1 - top - bottom)
        top += open * close * 0.8
        bottom += open * close * 0.2
        v.topLid = top
        v.bottomLid = bottom
        v.lidTilt = e.lidTilt * (1 - close)
        v.bottomArch = e.bottomArch * (1 - close)
        v.browTilt = e.browTilt
        v.browRaise = e.browRaise - close * 0.35
        v.pupilScale = e.pupilScale * pupilScale
        v.redness = redness
        v.dizzy = dizzy
        v.dizzyPhase = dizzyPhase
        return v
    }

    func isClose(to o: EyeVisual, tolerance t: Double = 0.004) -> Bool {
        abs(gaze.x - o.gaze.x) < t && abs(gaze.y - o.gaze.y) < t
            && abs(topLid - o.topLid) < t && abs(bottomLid - o.bottomLid) < t
            && abs(lidTilt - o.lidTilt) < t && abs(bottomArch - o.bottomArch) < t
            && abs(browTilt - o.browTilt) < t && abs(browRaise - o.browRaise) < t
            && abs(pupilScale - o.pupilScale) < t && abs(redness - o.redness) < t
            && abs(dizzy - o.dizzy) < t && (dizzy < 0.5 || abs(dizzyPhase - o.dizzyPhase) < t)
            && side == o.side
    }
}

/// Places a row of eyes inside a rectangle.
enum EyeLayout {
    /// Extra height above each eye that is kept free for the eyebrow.
    static let browFraction = 0.32

    static func eyeHeight(forTotalHeight h: CGFloat, showBrow: Bool) -> CGFloat {
        showBrow ? h / (1 + browFraction) : h
    }

    static func totalHeight(eyeHeight h: CGFloat, showBrow: Bool) -> CGFloat {
        showBrow ? h * (1 + browFraction) : h
    }

    static func gap(eyeWidth w: CGFloat, spacing: Double) -> CGFloat {
        w * (0.06 + CGFloat(spacing) * 0.9)
    }

    static func contentWidth(count: Int, eyeHeight: CGFloat, aspect: Double, spacing: Double) -> CGFloat {
        let n = CGFloat(max(1, count))
        let w = eyeHeight * CGFloat(aspect)
        return n * w + (n - 1) * gap(eyeWidth: w, spacing: spacing)
    }

    static func rects(count: Int, in bounds: CGRect, aspect: Double, spacing: Double, showBrow: Bool) -> [CGRect] {
        let n = max(1, count)
        guard bounds.width > 0, bounds.height > 0 else { return [] }
        var eyeH = eyeHeight(forTotalHeight: bounds.height, showBrow: showBrow)
        var total = contentWidth(count: n, eyeHeight: eyeH, aspect: aspect, spacing: spacing)
        if total > bounds.width {
            eyeH *= bounds.width / total
            total = bounds.width
        }
        let w = eyeH * CGFloat(aspect)
        let g = gap(eyeWidth: w, spacing: spacing)
        let blockH = totalHeight(eyeHeight: eyeH, showBrow: showBrow)
        let x0 = bounds.midX - total / 2
        let y0 = bounds.midY - blockH / 2
        return (0..<n).map { i in
            CGRect(x: x0 + CGFloat(i) * (w + g), y: y0, width: w, height: eyeH)
        }
    }

    /// Eyes come in pairs: even index is a left eye, odd index is a right eye.
    static func side(index: Int, count: Int) -> Double {
        if count <= 1 { return 0 }
        if count % 2 == 1 && index == count - 1 { return 0 }
        return index % 2 == 0 ? -1 : 1
    }
}

/// Draws eyes with Core Graphics. The context must have y pointing up.
enum EyeRenderer {
    static func draw(_ v: EyeVisual, theme: Theme, in rect: CGRect, ctx: CGContext, showBrow: Bool) {
        guard rect.width > 1, rect.height > 1 else { return }
        let lw = max(0.75, rect.height * 0.045)
        let body = rect.insetBy(dx: lw / 2, dy: lw / 2)
        let rx = body.width / 2
        let ry = body.height / 2
        let cx = body.midX
        let cy = body.midY
        let sclera = CGPath(ellipseIn: body, transform: nil)
        // Positive slope lowers the right-hand side of a lid or brow.
        let lidSlope = CGFloat(-v.side * v.lidTilt)
        let browSlope = CGFloat(-v.side * v.browTilt)

        ctx.saveGState()
        ctx.addPath(sclera)
        ctx.setFillColor(theme.sclera.mixed(with: RGBA(1.0, 0.40, 0.38), v.redness * 0.5).cg)
        ctx.fillPath()
        ctx.addPath(sclera)
        ctx.clip()

        if v.redness > 0.25 && rect.height >= 28 {
            drawVeins(ctx: ctx, cx: cx, cy: cy, rx: rx, ry: ry, lw: lw, amount: v.redness)
        }

        // Iris and pupil.
        let irisR = CGFloat(theme.irisRatio) * ry
        var pupilR = CGFloat(theme.pupilRatio * v.pupilScale) * ry
        if irisR > 0 { pupilR = min(pupilR, irisR * 0.86) }
        let discR = max(irisR, pupilR)
        let travelX = max(0, rx - discR * 0.92)
        let travelY = max(0, ry - discR * 0.92)
        let px = cx + v.gaze.x * travelX
        let py = cy + v.gaze.y * travelY

        if irisR > 0 {
            let irisRect = CGRect(x: px - irisR, y: py - irisR, width: irisR * 2, height: irisR * 2)
            ctx.setFillColor(theme.iris.cg)
            ctx.fillEllipse(in: irisRect)
            ctx.setStrokeColor(theme.iris.darker(0.4).cg)
            ctx.setLineWidth(lw * 0.7)
            ctx.strokeEllipse(in: irisRect.insetBy(dx: lw * 0.35, dy: lw * 0.35))
        }

        if v.dizzy > 0.5 {
            drawSpiral(ctx: ctx, cx: px, cy: py, radius: max(discR, ry * 0.5) * 0.95, phase: v.dizzyPhase, color: theme.pupil)
        } else {
            ctx.saveGState()
            if theme.glow, let space = CGColorSpace(name: CGColorSpace.sRGB) {
                // A soft halo drawn as a gradient. Much cheaper than a blurred shadow.
                var halo = theme.pupil
                halo.a = 0.55
                var clear = theme.pupil
                clear.a = 0
                if let gradient = CGGradient(colorsSpace: space, colors: [halo.cg, clear.cg] as CFArray, locations: [0, 1]) {
                    let center = CGPoint(x: px, y: py)
                    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: pupilR * 0.6,
                                           endCenter: center, endRadius: pupilR * 2.3, options: [])
                }
            }
            ctx.setFillColor(theme.pupil.cg)
            switch theme.pupilShape {
            case .round:
                ctx.fillEllipse(in: CGRect(x: px - pupilR, y: py - pupilR, width: pupilR * 2, height: pupilR * 2))
            case .slit:
                let halfH = irisR > 0 ? irisR * 0.92 : pupilR * 1.5
                let halfW = pupilR * 0.42
                ctx.fillEllipse(in: CGRect(x: px - halfW, y: py - halfH, width: halfW * 2, height: halfH * 2))
            case .square:
                let s = pupilR * 1.7
                let r = CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil))
                ctx.fillPath()
            }
            ctx.restoreGState()

            if theme.highlight.a > 0.01 && pupilR >= 2.2 {
                let hr = pupilR * 0.27
                ctx.setFillColor(theme.highlight.cg)
                ctx.fillEllipse(in: CGRect(x: px - pupilR * 0.34 - hr, y: py + pupilR * 0.36 - hr, width: hr * 2, height: hr * 2))
            }
        }

        // Top lid.
        if v.topLid > 0.004 {
            let y = body.maxY - CGFloat(v.topLid) * body.height
            let k = ry * 0.5 * lidSlope
            let yL = y + k
            let yR = y - k
            let arch = ry * 0.55 * CGFloat(1 - v.topLid)
            let left = CGPoint(x: body.minX - 2, y: yL)
            let right = CGPoint(x: body.maxX + 2, y: yR)
            let control = CGPoint(x: cx, y: (yL + yR) / 2 + arch)
            ctx.move(to: CGPoint(x: body.minX - 2, y: body.maxY + 2))
            ctx.addLine(to: CGPoint(x: body.maxX + 2, y: body.maxY + 2))
            ctx.addLine(to: right)
            ctx.addQuadCurve(to: left, control: control)
            ctx.closePath()
            ctx.setFillColor(theme.lid.cg)
            ctx.fillPath()
            ctx.move(to: right)
            ctx.addQuadCurve(to: left, control: control)
            ctx.setStrokeColor(theme.outline.cg)
            ctx.setLineWidth(lw * 0.8)
            ctx.strokePath()
        }

        // Bottom lid.
        if v.bottomLid > 0.004 {
            let y = body.minY + CGFloat(v.bottomLid) * body.height
            let arch = ry * 0.6 * CGFloat(v.bottomArch) * CGFloat(1 - v.bottomLid)
            let left = CGPoint(x: body.minX - 2, y: y)
            let right = CGPoint(x: body.maxX + 2, y: y)
            let control = CGPoint(x: cx, y: y + arch)
            ctx.move(to: CGPoint(x: body.minX - 2, y: body.minY - 2))
            ctx.addLine(to: CGPoint(x: body.maxX + 2, y: body.minY - 2))
            ctx.addLine(to: right)
            ctx.addQuadCurve(to: left, control: control)
            ctx.closePath()
            ctx.setFillColor(theme.lid.cg)
            ctx.fillPath()
            ctx.move(to: right)
            ctx.addQuadCurve(to: left, control: control)
            ctx.setStrokeColor(theme.outline.cg)
            ctx.setLineWidth(lw * 0.8)
            ctx.strokePath()
        }
        ctx.restoreGState()

        ctx.addPath(sclera)
        ctx.setStrokeColor(theme.outline.cg)
        ctx.setLineWidth(lw)
        ctx.strokePath()

        if showBrow {
            let half = rx * 0.95
            let by = rect.maxY + rect.height * CGFloat(0.13 + 0.07 * v.browRaise)
            ctx.saveGState()
            ctx.translateBy(x: cx, y: by)
            ctx.rotate(by: -browSlope * 0.42)
            ctx.move(to: CGPoint(x: -half, y: 0))
            ctx.addQuadCurve(to: CGPoint(x: half, y: 0), control: CGPoint(x: 0, y: rect.height * 0.1))
            ctx.setStrokeColor(theme.brow.cg)
            ctx.setLineWidth(max(1.2, rect.height * 0.105))
            ctx.setLineCap(.round)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    private static func drawVeins(ctx: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, lw: CGFloat, amount: Double) {
        ctx.saveGState()
        ctx.setStrokeColor(RGBA(0.85, 0.12, 0.12, min(0.75, amount * 0.75)).cg)
        ctx.setLineWidth(max(0.6, lw * 0.45))
        ctx.setLineCap(.round)
        for k in 0..<7 {
            let a = CGFloat(k) * 0.9 + 0.35
            let ex = cx + cos(a) * rx
            let ey = cy + sin(a) * ry
            let mx = cx + cos(a + 0.22) * rx * 0.74
            let my = cy + sin(a + 0.22) * ry * 0.74
            let ix = cx + cos(a - 0.1) * rx * 0.52
            let iy = cy + sin(a - 0.1) * ry * 0.52
            ctx.move(to: CGPoint(x: ex, y: ey))
            ctx.addLine(to: CGPoint(x: mx, y: my))
            ctx.addLine(to: CGPoint(x: ix, y: iy))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawSpiral(ctx: CGContext, cx: CGFloat, cy: CGFloat, radius: CGFloat, phase: Double, color: RGBA) {
        ctx.saveGState()
        let steps = 72
        let turns = 2.6
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let a = t * turns * 2 * Double.pi + phase
            let r = radius * CGFloat(t)
            let p = CGPoint(x: cx + CGFloat(cos(a)) * r, y: cy + CGFloat(sin(a)) * r)
            if i == 0 { ctx.move(to: p) } else { ctx.addLine(to: p) }
        }
        ctx.setStrokeColor(color.cg)
        ctx.setLineWidth(max(1, radius * 0.17))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Renders a row of eyes into a bitmap. Used by the widget, the icon and the preview sheet.
    static func image(size: CGSize, scale: CGFloat, count: Int, theme: Theme, spacing: Double,
                      showBrow: Bool, padding: CGFloat, visual: (Int) -> EyeVisual) -> CGImage? {
        let pw = Int((size.width * scale).rounded())
        let ph = Int((size.height * scale).rounded())
        guard pw > 0, ph > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let area = CGRect(origin: .zero, size: size).insetBy(dx: padding, dy: padding)
        let rects = EyeLayout.rects(count: count, in: area, aspect: theme.aspect, spacing: spacing, showBrow: showBrow)
        for (i, r) in rects.enumerated() {
            draw(visual(i), theme: theme, in: r, ctx: ctx, showBrow: showBrow)
        }
        return ctx.makeImage()
    }
}
