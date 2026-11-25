import AppKit
import CoreGraphics
import Foundation

// Draws the MacEye app icon at every size macOS needs.
// Usage: make_icon <path to AppIcon.appiconset>

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    print("usage: make_icon <AppIcon.appiconset folder>")
    exit(1)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func renderIcon(pixels: Int) -> Data? {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let s = CGFloat(pixels)
    // macOS icons sit inside a margin, with a rounded-square plate.
    let plate = CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.098, dy: s * 0.098)
    let radius = plate.width * 0.225
    let path = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(srgbRed: 0.10, green: 0.45, blue: 0.48, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [CGColor(srgbRed: 0.16, green: 0.72, blue: 0.66, alpha: 1),
                  CGColor(srgbRed: 0.13, green: 0.29, blue: 0.56, alpha: 1)] as CFArray
    if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: plate.minX, y: plate.maxY),
                               end: CGPoint(x: plate.maxX, y: plate.minY), options: [])
    }
    ctx.restoreGState()

    let theme = Theme.classic
    let area = plate.insetBy(dx: plate.width * 0.13, dy: plate.height * 0.24)
    let rects = EyeLayout.rects(count: 2, in: area, aspect: theme.aspect, spacing: 0.08, showBrow: false)
    for (i, rect) in rects.enumerated() {
        let visual = EyeVisual.make(side: EyeLayout.side(index: i, count: 2), gaze: CGPoint(x: 0.5, y: 0.45),
                                    expression: EyePose(), closure: 0, moodLids: false)
        EyeRenderer.draw(visual, theme: theme, in: rect, ctx: ctx, showBrow: false)
    }

    guard let image = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for entry in sizes {
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    guard let data = renderIcon(pixels: entry.points * entry.scale) else {
        print("could not draw \(name)")
        exit(1)
    }
    try data.write(to: folder.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(entry.points)x\(entry.points)", "scale": "\(entry.scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: folder.appendingPathComponent("Contents.json"))
print("wrote \(sizes.count) icon images to \(folder.path)")
