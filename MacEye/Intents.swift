import AppIntents
import AppKit

// Actions for the Shortcuts app.

struct BlinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Blink Eyes"
    static var description = IntentDescription("Makes the MacEye eyes blink once.")

    @MainActor
    func perform() async throws -> some IntentResult {
        EyeEngine.shared.blink()
        return .result()
    }
}

struct SetMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Eye Mood"
    static var description = IntentDescription("Changes the mood of the MacEye eyes.")

    @Parameter(title: "Mood")
    var mood: Mood

    static var parameterSummary: some ParameterSummary {
        Summary("Set eye mood to \(\.$mood)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ConfigStore.shared.config.mood = mood
        return .result()
    }
}

struct SetThemeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Eye Theme"
    static var description = IntentDescription("Changes the look of the MacEye eyes.")

    @Parameter(title: "Theme")
    var theme: ThemeChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Set eye theme to \(\.$theme)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ConfigStore.shared.config.themeID = theme.rawValue
        return .result()
    }
}

struct SetFloatingEyesIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Floating Eyes"
    static var description = IntentDescription("Shows or hides the floating desktop eyes.")

    @Parameter(title: "Show", default: true)
    var show: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Show floating eyes: \(\.$show)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ConfigStore.shared.config.showFloating = show
        return .result()
    }
}

struct SetEyesHiddenIntent: AppIntent {
    static var title: LocalizedStringResource = "Hide All Eyes"
    static var description = IntentDescription("Hides or shows every pair of MacEye eyes.")

    @Parameter(title: "Hide", default: true)
    var hide: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Hide all eyes: \(\.$hide)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ConfigStore.shared.config.eyesHidden = hide
        return .result()
    }
}

struct FindPointerIntent: AppIntent {
    static var title: LocalizedStringResource = "Find My Pointer"
    static var description = IntentDescription("Highlights the mouse pointer and makes the eyes stare at it.")

    @MainActor
    func perform() async throws -> some IntentResult {
        EyeEngine.shared.findPointer()
        return .result()
    }
}
