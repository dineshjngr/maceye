import AppKit
import Carbon.HIToolbox
import SwiftUI

/// System-wide keyboard shortcuts. Uses the Carbon hot key API, which needs no special permission.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var handler: ((HotKeyAction) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: HotKeyAction] = [:]
    private var current: [String: HotKeyCombo] = [:]
    private var installed = false

    /// Set while the user records a new shortcut, so existing shortcuts do not fire.
    var paused = false {
        didSet {
            guard paused != oldValue else { return }
            register(current)
        }
    }

    func register(_ map: [String: HotKeyCombo]) {
        current = map
        unregisterAll()
        guard !paused else { return }
        installHandlerIfNeeded()
        var id: UInt32 = 1
        for action in HotKeyAction.allCases {
            defer { id += 1 }
            guard let combo = map[action.rawValue] else { continue }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4D43_4559), id: id)
            let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actionsByID[id] = action
            }
        }
    }

    private func unregisterAll() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        actionsByID.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if status == noErr {
                HotKeyCenter.shared.fire(hotKeyID.id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }

    private func fire(_ id: UInt32) {
        guard let action = actionsByID[id] else { return }
        handler?(action)
    }
}

extension HotKeyCombo {
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + KeyNames.name(for: keyCode)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }
}

enum KeyNames {
    private static let special: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func name(for keyCode: UInt32) -> String {
        if let name = special[keyCode] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status: OSStatus = data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(-1) }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// A small box that records a keyboard shortcut when clicked.
final class RecorderField: NSView {
    var combo: HotKeyCombo? { didSet { refresh() } }
    var onChange: ((HotKeyCombo?) -> Void)?

    private var recording = false
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    private func refresh() {
        if recording {
            label.stringValue = "Press shortcut…"
            label.textColor = .controlAccentColor
        } else if let combo {
            label.stringValue = combo.display
            label.textColor = .labelColor
        } else {
            label.stringValue = "Click to record"
            label.textColor = .secondaryLabelColor
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = (recording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        recording = true
        HotKeyCenter.shared.paused = true
        window?.makeFirstResponder(self)
        refresh()
    }

    private func stop() {
        recording = false
        HotKeyCenter.shared.paused = false
        refresh()
    }

    override func resignFirstResponder() -> Bool {
        if recording { stop() }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return false }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        let modifiers = HotKeyCombo.carbonModifiers(from: event.modifierFlags)
        if event.keyCode == 53 && modifiers == 0 {
            stop()
            return
        }
        if (event.keyCode == 51 || event.keyCode == 117) && modifiers == 0 {
            combo = nil
            onChange?(nil)
            stop()
            return
        }
        let required = UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey)
        guard modifiers & required != 0 else {
            NSSound.beep()
            return
        }
        let new = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        combo = new
        onChange?(new)
        stop()
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var combo: HotKeyCombo?

    func makeNSView(context: Context) -> RecorderField {
        let field = RecorderField()
        field.combo = combo
        field.onChange = { new in combo = new }
        return field
    }

    func updateNSView(_ field: RecorderField, context: Context) {
        if field.combo != combo { field.combo = combo }
        field.onChange = { new in combo = new }
    }
}
