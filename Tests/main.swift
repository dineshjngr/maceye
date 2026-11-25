import AppKit
import CoreGraphics
import Foundation
import QuartzCore

// Self-contained checks for the parts of MacEye that do not need a running app:
// settings, layout maths, and the two eye renderers. Run with Scripts/test.sh.
//
// Pass a folder as the first argument to also save comparison pictures there.

var failures = 0
var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-9) -> Bool { abs(a - b) <= tolerance }

// MARK: Settings

do {
    let defaults = Config()
    let data = defaults.encoded()
    check(data != nil, "default settings encode")
    if let data {
        check(Config.decode(data) == defaults, "settings survive an encode and decode round trip")
    }

    let partial = Config.decode(Data(#"{"themeID":"cat","eyeCount":4}"#.utf8))
    check(partial?.themeID == "cat", "partial settings keep the stored theme")
    check(partial?.eyeCount == 4, "partial settings keep the stored eye count")
    check(partial?.randomBlink == defaults.randomBlink, "partial settings fill missing keys with defaults")
    check(partial?.hotkeys == defaults.hotkeys, "partial settings keep the default shortcuts")

    let unknown = Config.decode(Data(#"{"notARealSetting":true}"#.utf8))
    check(unknown != nil, "unknown keys are ignored")
    check(Config.decode(Data(#"{"eyeCount":"many"}"#.utf8)) == nil, "a wrong value type is rejected")
    check(Config.decode(Data("not json".utf8)) == nil, "invalid JSON is rejected")

    var custom = Config()
    custom.themeID = "cartoon"
    custom.useCustomColors = true
    custom.customIris = RGBA(hex: 0x00FF00)
    check(custom.theme.iris == RGBA(hex: 0x00FF00), "custom colours override the theme")
    custom.useCustomColors = false
    check(custom.theme.iris == Theme.cartoon.iris, "theme colours are used when custom colours are off")
}

// MARK: Themes and moods

do {
    let ids = Theme.all.map(\.id)
    check(Set(ids).count == ids.count, "theme identifiers are unique")
    check(Theme.named("does-not-exist") == Theme.classic, "an unknown theme falls back to Classic")
    for theme in Theme.all {
        check(theme.aspect > 0.5 && theme.aspect < 1.5, "\(theme.name) has a sensible shape")
        check(theme.pupilRatio > 0 && theme.pupilRatio < 1, "\(theme.name) has a sensible pupil size")
    }
    for mood in Mood.allCases {
        let pose = EyePose.forMood(mood)
        check(pose.topLid >= 0 && pose.bottomLid >= 0 && pose.topLid + pose.bottomLid < 1, "\(mood.rawValue) keeps the eye open")
    }
    var pose = EyePose()
    let target = EyePose.forMood(.angry)
    for _ in 0..<200 { pose.approach(target, 0.2) }
    check(pose.distance(to: target) < 1e-6, "a pose settles on its target")
}

// MARK: Layout

do {
    let bounds = CGRect(x: 10, y: 20, width: 400, height: 100)
    for count in 1...8 {
        for showBrow in [false, true] {
            let rects = EyeLayout.rects(count: count, in: bounds, aspect: 0.9, spacing: 0.2, showBrow: showBrow)
            check(rects.count == count, "\(count) eyes produce \(count) rectangles")
            for rect in rects {
                check(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect), "eye \(count)/\(showBrow) stays inside its area")
            }
            for pair in zip(rects, rects.dropFirst()) {
                check(pair.0.maxX <= pair.1.minX + 0.01, "eyes do not overlap")
            }
            if showBrow, let first = rects.first {
                check(first.maxY + first.height * CGFloat(EyeLayout.browFraction) <= bounds.maxY + 0.01, "room is kept for eyebrows")
            }
        }
    }
    check(EyeLayout.rects(count: 3, in: .zero, aspect: 1, spacing: 0, showBrow: false).isEmpty, "an empty area gives no eyes")
    check(EyeLayout.side(index: 0, count: 1) == 0, "a single eye is centred")
    check(EyeLayout.side(index: 0, count: 2) == -1 && EyeLayout.side(index: 1, count: 2) == 1, "two eyes are left and right")
    check(EyeLayout.side(index: 4, count: 5) == 0, "the odd eye out is centred")
    let narrow = EyeLayout.contentWidth(count: 2, eyeHeight: 20, aspect: 1, spacing: 0)
    let wide = EyeLayout.contentWidth(count: 2, eyeHeight: 20, aspect: 1, spacing: 1)
    check(wide > narrow, "more spacing makes the row wider")
}

// MARK: Eye state

do {
    let pose = EyePose.forMood(.sleepy)
    let shut = EyeVisual.make(side: -1, gaze: .zero, expression: pose, closure: 1, moodLids: true)
    check(near(shut.topLid + shut.bottomLid, 1, 1e-9), "a closed eye is fully covered")
    let open = EyeVisual.make(side: -1, gaze: .zero, expression: pose, closure: 0, moodLids: false)
    check(open.topLid == 0 && open.bottomLid == 0, "mood eyelids can be turned off")
    let blinkWithoutMoodLids = EyeVisual.make(side: 1, gaze: .zero, expression: pose, closure: 1, moodLids: false)
    check(near(blinkWithoutMoodLids.topLid + blinkWithoutMoodLids.bottomLid, 1, 1e-9), "blinking still works with mood eyelids off")
    check(shut.isClose(to: shut), "an eye state equals itself")
    check(!shut.isClose(to: open), "different eye states are told apart")
}

// MARK: Rendering

/// Draws one eye with the Core Graphics renderer.
func renderDirect(_ visual: EyeVisual, theme: Theme, size: CGSize, rect: CGRect, scale: CGFloat) -> CGContext? {
    guard let ctx = makeContext(size: size, scale: scale) else { return nil }
    EyeRenderer.draw(visual, theme: theme, in: rect, ctx: ctx, showBrow: true)
    return ctx
}

/// Draws the same eye with the Core Animation layers the live app uses.
func renderLayers(_ visual: EyeVisual, theme: Theme, size: CGSize, rect: CGRect, scale: CGFloat) -> CGContext? {
    guard let ctx = makeContext(size: size, scale: scale) else { return nil }
    let eye = EyeLayers()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    eye.configure(rect: rect, theme: theme, showBrow: true, scale: scale)
    eye.apply(visual)
    CATransaction.commit()
    ctx.translateBy(x: rect.minX, y: rect.minY)
    eye.root.render(in: ctx)
    return ctx
}

func makeContext(size: CGSize, scale: CGFloat) -> CGContext? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    return ctx
}

/// Average difference per colour channel, from 0 (identical) to 1.
func difference(_ a: CGContext, _ b: CGContext) -> Double {
    guard let pa = a.data, let pb = b.data, a.bytesPerRow == b.bytesPerRow, a.height == b.height else { return 1 }
    let count = a.bytesPerRow * a.height
    let ba = pa.bindMemory(to: UInt8.self, capacity: count)
    let bb = pb.bindMemory(to: UInt8.self, capacity: count)
    var total = 0
    for i in 0..<count { total += abs(Int(ba[i]) - Int(bb[i])) }
    return Double(total) / Double(count) / 255
}

func coverage(_ ctx: CGContext) -> Double {
    guard let data = ctx.data else { return 0 }
    let count = ctx.bytesPerRow * ctx.height
    let bytes = data.bindMemory(to: UInt8.self, capacity: count)
    var opaque = 0
    var i = 3
    while i < count {
        if bytes[i] > 128 { opaque += 1 }
        i += 4
    }
    return Double(opaque) / Double(count / 4)
}

func save(_ ctx: CGContext, to url: URL) {
    guard let image = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

do {
    let dumpFolder = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) : nil
    if let dumpFolder { try? FileManager.default.createDirectory(at: dumpFolder, withIntermediateDirectories: true) }

    let size = CGSize(width: 150, height: 170)
    let rect = CGRect(x: 25, y: 20, width: 100, height: 110)
    let cases: [(name: String, visual: EyeVisual)] = [
        ("neutral", EyeVisual.make(side: -1, gaze: CGPoint(x: 0.4, y: 0.3), expression: EyePose(), closure: 0, moodLids: true)),
        ("angry", EyeVisual.make(side: -1, gaze: CGPoint(x: -0.6, y: -0.2), expression: .forMood(.angry), closure: 0, moodLids: true)),
        ("happy", EyeVisual.make(side: 1, gaze: CGPoint(x: 0, y: 0.5), expression: .forMood(.happy), closure: 0, moodLids: true)),
        ("sad", EyeVisual.make(side: 1, gaze: CGPoint(x: 0.2, y: -0.5), expression: .forMood(.sad), closure: 0, moodLids: true)),
        ("blink", EyeVisual.make(side: -1, gaze: .zero, expression: EyePose(), closure: 0.6, moodLids: true)),
        ("closed", EyeVisual.make(side: 0, gaze: .zero, expression: EyePose(), closure: 1, moodLids: true)),
        ("tired", EyeVisual.make(side: -1, gaze: CGPoint(x: 0.3, y: 0), expression: .forMood(.sleepy), closure: 0, moodLids: true, redness: 0.9)),
        ("dizzy", EyeVisual.make(side: 1, gaze: .zero, expression: EyePose(), closure: 0, moodLids: true, dizzy: 1, dizzyPhase: 0.6)),
    ]

    for theme in Theme.all {
        for item in cases {
            guard let direct = renderDirect(item.visual, theme: theme, size: size, rect: rect, scale: 2),
                  let layers = renderLayers(item.visual, theme: theme, size: size, rect: rect, scale: 2)
            else {
                check(false, "could not create a drawing context")
                continue
            }
            check(coverage(direct) > 0.15, "\(theme.name) \(item.name): the direct renderer draws an eye")
            check(coverage(layers) > 0.15, "\(theme.name) \(item.name): the layer renderer draws an eye")
            // The glow of the Robot theme is drawn differently by the two renderers, so it gets more room.
            let allowed = theme.glow ? 0.06 : 0.02
            let diff = difference(direct, layers)
            check(diff < allowed, "\(theme.name) \(item.name): renderers differ by \(String(format: "%.4f", diff)), allowed \(allowed)")
            if let dumpFolder {
                save(direct, to: dumpFolder.appendingPathComponent("\(theme.id)-\(item.name)-direct.png"))
                save(layers, to: dumpFolder.appendingPathComponent("\(theme.id)-\(item.name)-layers.png"))
            }
        }
    }

    let row = EyeRenderer.image(size: CGSize(width: 200, height: 80), scale: 2, count: 2, theme: .classic, spacing: 0.1,
                                showBrow: false, padding: 4) { index in
        EyeVisual.make(side: EyeLayout.side(index: index, count: 2), gaze: .zero, expression: EyePose(), closure: 0, moodLids: true)
    }
    check(row?.width == 400 && row?.height == 160, "the image renderer honours size and scale")
}

print("\(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
