import AppKit
import CoreGraphics
import Foundation

// Draws the README preview pictures: every theme in every mood, and every theme in every reaction.
// Usage: make_previews <output folder>

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("usage: make_previews <output folder>")
    exit(1)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

struct Column {
    let title: String
    var pose = EyePose()
    var closure = 0.0
    var redness = 0.0
    var dizzy = 0.0
    var gaze = CGPoint(x: 0.35, y: 0.2)
}

func renderSheet(columns: [Column], to url: URL) -> Bool {
    let cell = CGSize(width: 170, height: 118)
    let labelHeight: CGFloat = 22
    let size = CGSize(width: cell.width * CGFloat(columns.count),
                      height: (cell.height + labelHeight) * CGFloat(Theme.all.count))
    let scale: CGFloat = 2
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return false }
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(CGColor(srgbRed: 0.91, green: 0.92, blue: 0.94, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.12, green: 0.14, blue: 0.18, alpha: 1),
    ]

    for (row, theme) in Theme.all.enumerated() {
        let y = size.height - CGFloat(row + 1) * (cell.height + labelHeight)
        for (index, column) in columns.enumerated() {
            let x = CGFloat(index) * cell.width
            let area = CGRect(x: x, y: y + labelHeight, width: cell.width, height: cell.height).insetBy(dx: 14, dy: 12)
            let rects = EyeLayout.rects(count: 2, in: area, aspect: theme.aspect, spacing: 0.12, showBrow: true)
            for (i, rect) in rects.enumerated() {
                let visual = EyeVisual.make(side: EyeLayout.side(index: i, count: 2), gaze: column.gaze,
                                            expression: column.pose, closure: column.closure, moodLids: true,
                                            redness: column.redness, dizzy: column.dizzy, dizzyPhase: 0.6)
                EyeRenderer.draw(visual, theme: theme, in: rect, ctx: ctx, showBrow: true)
            }
            ("\(theme.name) · \(column.title)" as NSString).draw(at: CGPoint(x: x + 10, y: y + 5), withAttributes: attributes)
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let image = ctx.makeImage(),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { return false }
    return (try? data.write(to: url)) != nil
}

let moods: [Mood] = [.neutral, .happy, .angry, .sad, .sleepy, .surprised, .suspicious]
let moodColumns = moods.map { Column(title: $0.title, pose: .forMood($0)) }

let reactionColumns = [
    Column(title: "Blinking", closure: 0.6),
    Column(title: "Dizzy", dizzy: 1),
    Column(title: "Busy CPU", pose: EyePose(topLid: 0.40, bottomLid: 0.08, lidTilt: 0.15, browTilt: 0.3, browRaise: -0.3), redness: 0.9),
    Column(title: "Asleep", closure: 1, gaze: CGPoint(x: 0, y: -0.4)),
    Column(title: "Typing", pose: .focused),
    Column(title: "Looking away", gaze: CGPoint(x: -0.7, y: -0.7)),
]

let ok = renderSheet(columns: moodColumns, to: folder.appendingPathComponent("moods.png"))
    && renderSheet(columns: reactionColumns, to: folder.appendingPathComponent("reactions.png"))
print(ok ? "wrote moods.png and reactions.png to \(folder.path)" : "could not write the preview pictures")
exit(ok ? 0 : 1)
