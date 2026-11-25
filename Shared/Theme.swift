import CoreGraphics
import Foundation

/// A plain sRGB colour that can be saved in settings.
struct RGBA: Codable, Equatable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    func mixed(with o: RGBA, _ t: Double) -> RGBA {
        let k = min(1, max(0, t))
        return RGBA(r + (o.r - r) * k, g + (o.g - g) * k, b + (o.b - b) * k, a + (o.a - a) * k)
    }

    func darker(_ t: Double) -> RGBA { mixed(with: RGBA(0, 0, 0, a), t) }
}

enum PupilShape: String, Codable {
    case round
    case slit
    case square
}

enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case neutral
    case happy
    case angry
    case sad
    case sleepy
    case surprised
    case suspicious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .neutral: return "Neutral"
        case .happy: return "Happy"
        case .angry: return "Angry"
        case .sad: return "Sad"
        case .sleepy: return "Sleepy"
        case .surprised: return "Surprised"
        case .suspicious: return "Suspicious"
        }
    }
}

/// Eyelid and eyebrow pose for one mood. All values are fractions of the eye size.
struct EyePose: Equatable {
    /// 0 = open, 1 = the top lid covers the whole eye.
    var topLid = 0.0
    var bottomLid = 0.0
    /// Positive lowers the inner corner (angry), negative lowers the outer corner (sad).
    var lidTilt = 0.0
    /// Positive arches the bottom lid upward (smiling eyes).
    var bottomArch = -0.3
    var browTilt = 0.0
    var browRaise = 0.0
    var pupilScale = 1.0

    static func forMood(_ mood: Mood) -> EyePose {
        switch mood {
        case .auto, .neutral:
            return EyePose()
        case .happy:
            return EyePose(topLid: 0, bottomLid: 0.34, lidTilt: 0, bottomArch: 1, browTilt: -0.25, browRaise: 0.45)
        case .angry:
            return EyePose(topLid: 0.30, bottomLid: 0, lidTilt: 0.85, browTilt: 1, browRaise: -0.6)
        case .sad:
            return EyePose(topLid: 0.26, bottomLid: 0, lidTilt: -0.75, browTilt: -0.95, browRaise: 0.15)
        case .sleepy:
            return EyePose(topLid: 0.52, bottomLid: 0, lidTilt: -0.1, browTilt: -0.15, browRaise: -0.3)
        case .surprised:
            return EyePose(topLid: 0, bottomLid: 0, browTilt: -0.1, browRaise: 1, pupilScale: 0.72)
        case .suspicious:
            return EyePose(topLid: 0.36, bottomLid: 0.30, lidTilt: 0.2, bottomArch: 0, browTilt: 0.35, browRaise: -0.5)
        }
    }

    /// Slight squint used while the user is typing.
    static let focused = EyePose(topLid: 0.22, bottomLid: 0.18, bottomArch: 0, browTilt: 0.15, browRaise: -0.25)

    mutating func approach(_ t: EyePose, _ k: Double) {
        topLid += (t.topLid - topLid) * k
        bottomLid += (t.bottomLid - bottomLid) * k
        lidTilt += (t.lidTilt - lidTilt) * k
        bottomArch += (t.bottomArch - bottomArch) * k
        browTilt += (t.browTilt - browTilt) * k
        browRaise += (t.browRaise - browRaise) * k
        pupilScale += (t.pupilScale - pupilScale) * k
    }

    func distance(to o: EyePose) -> Double {
        max(abs(topLid - o.topLid), abs(bottomLid - o.bottomLid), abs(lidTilt - o.lidTilt),
            abs(bottomArch - o.bottomArch), abs(browTilt - o.browTilt), abs(browRaise - o.browRaise),
            abs(pupilScale - o.pupilScale))
    }
}

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    var sclera: RGBA
    var iris: RGBA
    var pupil: RGBA
    var outline: RGBA
    var lid: RGBA
    var brow: RGBA
    var highlight: RGBA
    var pupilShape: PupilShape
    /// Iris radius as a fraction of half the eye height. 0 = no iris.
    var irisRatio: Double
    /// Pupil radius as a fraction of half the eye height.
    var pupilRatio: Double
    /// Eye width divided by eye height.
    var aspect: Double
    var glow: Bool
    /// Mood used when the mood setting is Automatic and nothing else is happening.
    var baseMood: Mood

    static let classic = Theme(
        id: "classic", name: "Classic",
        sclera: RGBA(hex: 0xFFFFFF), iris: RGBA(hex: 0x000000), pupil: RGBA(hex: 0x111111),
        outline: RGBA(hex: 0x1C1C1E), lid: RGBA(hex: 0xD6D6DC), brow: RGBA(hex: 0x1C1C1E),
        highlight: RGBA(1, 1, 1, 0.9), pupilShape: .round, irisRatio: 0, pupilRatio: 0.46,
        aspect: 0.86, glow: false, baseMood: .neutral)

    static let cartoon = Theme(
        id: "cartoon", name: "Cartoon",
        sclera: RGBA(hex: 0xFFFFFF), iris: RGBA(hex: 0x3B82F6), pupil: RGBA(hex: 0x0B1220),
        outline: RGBA(hex: 0x1F2937), lid: RGBA(hex: 0xF2C9A0), brow: RGBA(hex: 0x5B3A1E),
        highlight: RGBA(1, 1, 1, 0.95), pupilShape: .round, irisRatio: 0.62, pupilRatio: 0.30,
        aspect: 0.92, glow: false, baseMood: .neutral)

    static let cat = Theme(
        id: "cat", name: "Cat",
        sclera: RGBA(hex: 0xE4D43A), iris: RGBA(hex: 0x8BB32A), pupil: RGBA(hex: 0x0A0A0A),
        outline: RGBA(hex: 0x1A1A1A), lid: RGBA(hex: 0x4B4B4F), brow: RGBA(hex: 0x2B2B2E),
        highlight: RGBA(1, 1, 1, 0.85), pupilShape: .slit, irisRatio: 0.80, pupilRatio: 0.42,
        aspect: 1.12, glow: false, baseMood: .neutral)

    static let robot = Theme(
        id: "robot", name: "Robot",
        sclera: RGBA(hex: 0x0F141B), iris: RGBA(hex: 0x000000), pupil: RGBA(hex: 0x22D3EE),
        outline: RGBA(hex: 0x7B8AA0), lid: RGBA(hex: 0x334155), brow: RGBA(hex: 0x7B8AA0),
        highlight: RGBA(1, 1, 1, 0), pupilShape: .square, irisRatio: 0, pupilRatio: 0.40,
        aspect: 1.0, glow: true, baseMood: .neutral)

    static let sleepy = Theme(
        id: "sleepy", name: "Sleepy",
        sclera: RGBA(hex: 0xF6F1FF), iris: RGBA(hex: 0x8B7FD1), pupil: RGBA(hex: 0x241E47),
        outline: RGBA(hex: 0x3B3366), lid: RGBA(hex: 0xC6B6EE), brow: RGBA(hex: 0x3B3366),
        highlight: RGBA(1, 1, 1, 0.9), pupilShape: .round, irisRatio: 0.60, pupilRatio: 0.30,
        aspect: 0.95, glow: false, baseMood: .sleepy)

    static let angry = Theme(
        id: "angry", name: "Angry",
        sclera: RGBA(hex: 0xFFF3EE), iris: RGBA(hex: 0xD92B2B), pupil: RGBA(hex: 0x2B0A0A),
        outline: RGBA(hex: 0x3A0D0D), lid: RGBA(hex: 0x9A3A3A), brow: RGBA(hex: 0x3A0D0D),
        highlight: RGBA(1, 1, 1, 0.85), pupilShape: .round, irisRatio: 0.55, pupilRatio: 0.24,
        aspect: 0.95, glow: false, baseMood: .angry)

    static let all: [Theme] = [classic, cartoon, cat, robot, sleepy, angry]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? classic
    }
}
