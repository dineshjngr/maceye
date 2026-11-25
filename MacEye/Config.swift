import Combine
import Foundation

struct HotKeyCombo: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier flags (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: UInt32
}

enum HotKeyAction: String, CaseIterable, Identifiable {
    case blink
    case toggleEyes
    case cycleMood
    case findPointer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blink: return "Blink"
        case .toggleEyes: return "Hide or show the eyes"
        case .cycleMood: return "Change mood"
        case .findPointer: return "Find my pointer"
        }
    }
}

/// All user settings. Saved as JSON in UserDefaults.
struct Config: Codable, Equatable {
    // Look
    var themeID = "classic"
    var useCustomColors = false
    var customSclera = RGBA(hex: 0xFFFFFF)
    var customIris = RGBA(hex: 0x3B82F6)
    var customPupil = RGBA(hex: 0x111111)
    var mood: Mood = .auto
    var eyeCount = 2
    var spacing = 0.12
    var showEyebrows = false
    var showEyelids = true
    var adaptivePupil = true

    // Life
    var randomBlink = true
    var sleepWhenIdle = true
    var idleMinutes = 5.0
    var reactFastMouse = true
    var reactShake = true
    var reactTyping = true
    var googlyPhysics = false
    var followTextCursor = false

    // Useful
    var cpuTired = true
    var batteryTired = true
    var breakReminder = false
    var breakMinutes = 20.0
    var breakNotification = true
    var privacyClose = true

    // Placement
    var showMenuBar = true
    var menuBarSize = 0.85
    var showFloating = false
    var floatingSize = 110.0
    var floatingAllScreens = false
    var floatingOnTop = true
    /// Saved window origins. Not synced between Macs.
    var floatingPositions: [String: [Double]] = [:]
    var eyesHidden = false

    // Control
    var clickToBlink = true
    /// Control + Option + Command + B / H / M / F.
    var hotkeys: [String: HotKeyCombo] = [
        HotKeyAction.blink.rawValue: HotKeyCombo(keyCode: 11, modifiers: 6400),
        HotKeyAction.toggleEyes.rawValue: HotKeyCombo(keyCode: 4, modifiers: 6400),
        HotKeyAction.cycleMood.rawValue: HotKeyCombo(keyCode: 46, modifiers: 6400),
        HotKeyAction.findPointer.rawValue: HotKeyCombo(keyCode: 3, modifiers: 6400),
    ]
    var iCloudDriveSync = false

    var theme: Theme {
        var t = Theme.named(themeID)
        if useCustomColors {
            t.sclera = customSclera
            t.iris = customIris
            t.pupil = customPupil
        }
        return t
    }

    /// Decodes settings and fills any missing keys with the defaults,
    /// so settings saved by an older version still load.
    static func decode(_ data: Data) -> Config? {
        guard let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(Config()),
              var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return nil }
        for (key, value) in stored { merged[key] = value }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: mergedData)
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try? encoder.encode(self)
    }
}

final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    private static let key = "config.v1"

    @Published var config: Config {
        didSet {
            if config != oldValue { save() }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key), let saved = Config.decode(data) {
            config = saved
        } else {
            config = Config()
        }
    }

    private func save() {
        if let data = config.encoded() {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func reset() {
        config = Config()
    }
}
