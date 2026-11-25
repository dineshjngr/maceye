import SwiftUI
import WidgetKit

struct EyesEntry: TimelineEntry {
    let date: Date
    let theme: Theme
    let gaze: CGPoint
    let asleep: Bool
}

/// Widgets cannot animate or follow the pointer, so the eyes look in a new direction
/// every few minutes and sleep at night.
struct EyesProvider: TimelineProvider {
    let theme: Theme

    func placeholder(in context: Context) -> EyesEntry {
        EyesEntry(date: .now, theme: theme, gaze: CGPoint(x: 0.3, y: 0.2), asleep: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (EyesEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EyesEntry>) -> Void) {
        let step: TimeInterval = 5 * 60
        let start = Date(timeIntervalSinceReferenceDate: (Date.now.timeIntervalSinceReferenceDate / step).rounded(.down) * step)
        let entries = (0..<48).map { index in
            entry(for: start.addingTimeInterval(Double(index) * step))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(for date: Date) -> EyesEntry {
        let hour = Calendar.current.component(.hour, from: date)
        let night = hour >= 23 || hour < 6
        let slot = Int(date.timeIntervalSinceReferenceDate / 300)
        // A fixed pattern from the time slot, so every render of the same slot matches.
        let angle = Double(abs((slot &* 2_654_435_761) % 360)) * Double.pi / 180
        let reach = 0.35 + Double(abs((slot &* 40_503) % 60)) / 100
        let gaze = CGPoint(x: cos(angle) * reach, y: sin(angle) * reach)
        return EyesEntry(date: date, theme: theme, gaze: gaze, asleep: night)
    }
}

struct EyesWidgetView: View {
    let entry: EyesEntry
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            if let image = render(size: proxy.size) {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .accessibilityLabel(entry.asleep ? "Sleeping eyes" : "Eyes looking around")
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.30), Color(red: 0.07, green: 0.09, blue: 0.15)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func render(size: CGSize) -> CGImage? {
        var theme = entry.theme
        // The widget background is dark, so dark eyebrows need a lighter colour.
        if theme.brow.luminance < 0.4 { theme.brow = RGBA(0.92, 0.93, 0.96) }
        let pose = EyePose.forMood(theme.baseMood)
        return EyeRenderer.image(size: size, scale: displayScale, count: 2, theme: theme, spacing: 0.14,
                                 showBrow: true, padding: 6) { index in
            EyeVisual.make(side: EyeLayout.side(index: index, count: 2),
                           gaze: entry.asleep ? CGPoint(x: 0, y: -0.4) : entry.gaze,
                           expression: pose, closure: entry.asleep ? 1 : 0, moodLids: true)
        }
    }
}

/// One widget per theme. Plain widgets like these work without any developer signing.
private func eyesWidget(_ theme: Theme) -> some WidgetConfiguration {
    StaticConfiguration(kind: "MacEye.\(theme.id)", provider: EyesProvider(theme: theme)) { entry in
        EyesWidgetView(entry: entry)
    }
    .configurationDisplayName("MacEye \(theme.name)")
    .description("\(theme.name) eyes that look around and sleep at night.")
    .supportedFamilies([.systemSmall, .systemMedium])
}

struct ClassicEyesWidget: Widget {
    var body: some WidgetConfiguration { eyesWidget(.classic) }
}

struct CartoonEyesWidget: Widget {
    var body: some WidgetConfiguration { eyesWidget(.cartoon) }
}

struct CatEyesWidget: Widget {
    var body: some WidgetConfiguration { eyesWidget(.cat) }
}

struct RobotEyesWidget: Widget {
    var body: some WidgetConfiguration { eyesWidget(.robot) }
}

struct SleepyEyesWidget: Widget {
    var body: some WidgetConfiguration { eyesWidget(.sleepy) }
}

struct AngryEyesWidget: Widget {
    var body: some WidgetConfiguration { eyesWidget(.angry) }
}

@main
struct MacEyeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClassicEyesWidget()
        CartoonEyesWidget()
        CatEyesWidget()
        RobotEyesWidget()
        SleepyEyesWidget()
        AngryEyesWidget()
    }
}
