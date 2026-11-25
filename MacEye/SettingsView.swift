import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        VStack(spacing: 0) {
            EyesPreview()
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
                .accessibilityLabel("Live preview of the eyes")
            Divider()
            TabView {
                LookTab().tabItem { Label("Look", systemImage: "eye") }
                LifeTab().tabItem { Label("Life", systemImage: "sparkles") }
                UsefulTab().tabItem { Label("Useful", systemImage: "heart") }
                PlacementTab().tabItem { Label("Placement", systemImage: "macwindow") }
                ControlTab().tabItem { Label("Control", systemImage: "keyboard") }
                GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            }
            .padding(.top, 8)
        }
        .frame(width: 580, height: 700)
    }
}

private extension ConfigStore {
    func color(_ keyPath: WritableKeyPath<Config, RGBA>) -> Binding<Color> {
        Binding(
            get: {
                let c = self.config[keyPath: keyPath]
                return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
            },
            set: { new in
                guard let ns = NSColor(new).usingColorSpace(.sRGB) else { return }
                self.config[keyPath: keyPath] = RGBA(Double(ns.redComponent), Double(ns.greenComponent),
                                                     Double(ns.blueComponent), Double(ns.alphaComponent))
            })
    }
}

private struct LookTab: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: $store.config.themeID) {
                    ForEach(Theme.all) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                Toggle("Use my own colours", isOn: $store.config.useCustomColors)
                if store.config.useCustomColors {
                    ColorPicker("Eye white", selection: store.color(\.customSclera))
                    ColorPicker("Iris", selection: store.color(\.customIris))
                    ColorPicker("Pupil", selection: store.color(\.customPupil))
                    if store.config.theme.irisRatio == 0 {
                        Text("This theme has no iris, so the iris colour is not shown.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Mood") {
                Picker("Mood", selection: $store.config.mood) {
                    ForEach(Mood.allCases) { mood in
                        Text(mood.title).tag(mood)
                    }
                }
                Text("Automatic changes the mood with what happens on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Eyebrows", isOn: $store.config.showEyebrows)
                Toggle("Eyelids show the mood", isOn: $store.config.showEyelids)
            }
            Section("Shape") {
                Stepper(value: $store.config.eyeCount, in: 1...8) {
                    LabeledContent("Number of eyes", value: "\(store.config.eyeCount)")
                }
                Slider(value: $store.config.spacing, in: 0...1) {
                    Text("Space between eyes")
                }
                Toggle("Bigger pupils in Dark Mode, smaller in Light Mode", isOn: $store.config.adaptivePupil)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LifeTab: View {
    @EnvironmentObject var store: ConfigStore
    @State private var trusted = FocusTracker.isTrusted

    var body: some View {
        Form {
            Section("Blinking and sleep") {
                Toggle("Blink naturally", isOn: $store.config.randomBlink)
                Toggle("Fall asleep when the Mac is not used", isOn: $store.config.sleepWhenIdle)
                if store.config.sleepWhenIdle {
                    Slider(value: $store.config.idleMinutes, in: 1...30, step: 1) {
                        Text("Sleep after \(Int(store.config.idleMinutes)) min")
                    }
                }
            }
            Section("Reactions") {
                Toggle("Wide eyes when the pointer moves fast", isOn: $store.config.reactFastMouse)
                Toggle("Dizzy eyes when you shake the pointer", isOn: $store.config.reactShake)
                Toggle("Squint while you type", isOn: $store.config.reactTyping)
            }
            Section("Movement") {
                Toggle("Googly physics (pupils wobble and bounce)", isOn: $store.config.googlyPhysics)
                Toggle("Look at where you are typing", isOn: $store.config.followTextCursor)
                if store.config.followTextCursor {
                    if trusted {
                        Text("The eyes follow the text cursor while you type.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Without Accessibility access the eyes look at the front window. Allow access to follow the exact text cursor.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Allow Accessibility Access…") {
                            FocusTracker.requestAccess()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            trusted = FocusTracker.isTrusted
        }
    }
}

private struct UsefulTab: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Mac status") {
                Toggle("Red, tired eyes when the CPU is very busy", isOn: $store.config.cpuTired)
                Toggle("Sleepy eyes when the battery is low", isOn: $store.config.batteryTired)
            }
            Section("Eye breaks") {
                Toggle("Remind me to rest my eyes", isOn: $store.config.breakReminder)
                if store.config.breakReminder {
                    Slider(value: $store.config.breakMinutes, in: 5...60, step: 5) {
                        Text("Every \(Int(store.config.breakMinutes)) min")
                    }
                    Toggle("Also send a notification", isOn: $store.config.breakNotification)
                    Text("The eyes droop when a break is due. Stop using the Mac for 20 seconds and look far away to reset them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Privacy signal") {
                Toggle("Close the eyes while the microphone or camera is in use", isOn: $store.config.privacyClose)
                Text("MacEye only checks the “in use” status. It never listens or records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Pointer") {
                LabeledContent("Find my pointer") {
                    Button("Try It") { EyeEngine.shared.findPointer() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PlacementTab: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show eyes in the menu bar", isOn: $store.config.showMenuBar)
                Slider(value: $store.config.menuBarSize, in: 0.5...1.0) {
                    Text("Size")
                }
                .disabled(!store.config.showMenuBar)
            }
            Section("Floating eyes") {
                Toggle("Show floating eyes on the desktop", isOn: $store.config.showFloating)
                Group {
                    Slider(value: $store.config.floatingSize, in: 40...320) {
                        Text("Size")
                    }
                    Toggle("One pair on every display", isOn: $store.config.floatingAllScreens)
                    Toggle("Keep on top of other windows", isOn: $store.config.floatingOnTop)
                    LabeledContent("Position") {
                        Button("Reset") { store.config.floatingPositions = [:] }
                    }
                }
                .disabled(!store.config.showFloating)
                Text("Drag the floating eyes to move them. Right-click them for the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Desktop widget") {
                Text("Right-click the desktop, choose Edit Widgets, then search for MacEye.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ControlTab: View {
    @EnvironmentObject var store: ConfigStore

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                ForEach(HotKeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 6) {
                            HotKeyRecorder(combo: Binding(
                                get: { store.config.hotkeys[action.rawValue] },
                                set: { store.config.hotkeys[action.rawValue] = $0 }))
                                .frame(width: 150, height: 24)
                            Button {
                                store.config.hotkeys[action.rawValue] = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Remove shortcut")
                            .accessibilityLabel("Remove shortcut for \(action.title)")
                            .disabled(store.config.hotkeys[action.rawValue] == nil)
                        }
                    }
                }
                Text("Click a box, then press the keys. Shortcuts work in every app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Mouse") {
                Toggle("Click an eye to make it blink", isOn: $store.config.clickToBlink)
                Text("Right-click the eyes to open the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Shortcuts app and scripts") {
                Text("MacEye understands links. Use them in the Shortcuts app with the “Open URLs” action, or in a script with the open command.")
                    .foregroundStyle(.secondary)
                Text("maceye://blink\nmaceye://find\nmaceye://mood/happy  (or next)\nmaceye://theme/cat\nmaceye://floating/on  (off, toggle)\nmaceye://hide/toggle\nmaceye://physics/toggle")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("MacEye also has its own Shortcuts actions (Blink Eyes, Set Eye Mood and more). macOS only shows those when the app is signed with an Apple developer account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject var store: ConfigStore
    @ObservedObject private var sync = SettingsSync.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Start-up") {
                Toggle("Open MacEye when I log in", isOn: Binding(
                    get: { launchAtLogin },
                    set: { wanted in
                        do {
                            if wanted {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }))
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Visibility") {
                Toggle("Hide all eyes", isOn: $store.config.eyesHidden)
                Text("If every pair of eyes is hidden, open MacEye again from the Applications folder or Spotlight to get back to these settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sync between Macs") {
                Toggle("Sync settings through iCloud Drive", isOn: $store.config.iCloudDriveSync)
                Text("Saves one small settings file in your own iCloud Drive. MacEye itself never connects to the internet. Status: \(sync.status)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("All settings") {
                    Button("Reset…", role: .destructive) { confirmReset = true }
                }
                LabeledContent("MacEye") {
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all MacEye settings?", isPresented: $confirmReset) {
            Button("Reset Settings", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This puts every setting back to how it was when you first opened MacEye.")
        }
    }
}
