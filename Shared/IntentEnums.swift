import AppIntents

extension Mood: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Mood"

    static var caseDisplayRepresentations: [Mood: DisplayRepresentation] = [
        .auto: "Automatic",
        .neutral: "Neutral",
        .happy: "Happy",
        .angry: "Angry",
        .sad: "Sad",
        .sleepy: "Sleepy",
        .surprised: "Surprised",
        .suspicious: "Suspicious",
    ]
}

/// The built-in themes, as a choice for Shortcuts actions and the widget.
enum ThemeChoice: String, AppEnum, CaseIterable {
    case classic
    case cartoon
    case cat
    case robot
    case sleepy
    case angry

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Theme"

    static var caseDisplayRepresentations: [ThemeChoice: DisplayRepresentation] = [
        .classic: "Classic",
        .cartoon: "Cartoon",
        .cat: "Cat",
        .robot: "Robot",
        .sleepy: "Sleepy",
        .angry: "Angry",
    ]

    var theme: Theme { Theme.named(rawValue) }
}
