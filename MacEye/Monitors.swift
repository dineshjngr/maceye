import AppKit
import ApplicationServices
import CoreAudio
import CoreMediaIO
import IOKit.ps

/// Watches CPU load and battery level. Everything is read locally.
final class SystemMonitor {
    private(set) var cpuLoad = 0.0
    private(set) var cpuHigh = false
    private(set) var batteryLow = false
    private(set) var batteryPercent: Int?

    private var lastTicks: (busy: Double, total: Double)?
    private var timer: Timer?
    private var counter = 0

    func start() {
        guard timer == nil else { return }
        _ = sampleCPU()
        sampleBattery()
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        if let usage = sampleCPU() {
            cpuLoad += (usage - cpuLoad) * 0.35
            if cpuLoad > 0.72 { cpuHigh = true } else if cpuLoad < 0.55 { cpuHigh = false }
        }
        counter += 1
        if counter % 10 == 0 { sampleBattery() }
    }

    private func sampleCPU() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let busy = user + system + nice
        let total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return nil }
        return (busy - last.busy) / (total - last.total)
    }

    private func sampleBattery() {
        batteryLow = false
        batteryPercent = nil
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }
        for source in list {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let percent = current * 100 / maximum
            let onBattery = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue
            batteryPercent = percent
            if onBattery && percent <= 20 { batteryLow = true }
        }
    }
}

/// Reports whether any app is using the microphone or a camera.
/// It only reads the "in use" flag. It never opens the microphone or camera itself.
final class PrivacyMonitor {
    private(set) var micActive = false
    private(set) var cameraActive = false
    var active: Bool { micActive || cameraActive }

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        poll()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        micActive = false
        cameraActive = false
    }

    private func poll() {
        micActive = Self.microphoneInUse()
        cameraActive = Self.cameraInUse()
    }

    /// System speech services keep an input open in the background. They are not a person on a call.
    private static let ignoredPrefixes = ["com.apple.corespeech", "com.apple.CoreSpeech", "com.apple.assistant", "com.apple.siri", "com.apple.Siri"]

    static func microphoneInUse() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return false }
        for id in ids {
            var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                            mScope: kAudioObjectPropertyScopeGlobal,
                                                            mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
            let bundleID = processBundleID(id)
            if ignoredPrefixes.contains(where: { bundleID.hasPrefix($0) }) { continue }
            return true
        }
        return false
    }

    private static func processBundleID(_ id: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return "" }
        return value.takeRetainedValue() as String
    }

    static func cameraInUse() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == 0 else { return false }
        for id in ids {
            var runningAddress = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                           mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                           mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var runningUsed: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &runningUsed, &running) == 0,
               running != 0 {
                return true
            }
        }
        return false
    }
}

/// Finds where the user is typing: the text cursor (needs Accessibility access)
/// or, as a fallback, the middle of the front window.
final class FocusTracker {
    private let queue = DispatchQueue(label: "maceye.focus", qos: .utility)
    private var busy = false
    private(set) var point: CGPoint?
    private(set) var updatedAt: CFTimeInterval = 0

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Call on the main thread. The result arrives a moment later in `point`.
    func refresh() {
        guard !busy else { return }
        busy = true
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        queue.async { [weak self] in
            let found = Self.caretPoint(primaryHeight: primaryHeight)
                ?? Self.frontWindowCenter(pid: frontPID, primaryHeight: primaryHeight)
            DispatchQueue.main.async {
                guard let self else { return }
                self.point = found
                self.updatedAt = CACurrentMediaTime()
                self.busy = false
            }
        }
    }

    private static func caretPoint(primaryHeight: CGFloat) -> CGPoint? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let element = focused as! AXUIElement
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
              let range
        else { return nil }
        var bounds: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &bounds) == .success,
              let bounds, CFGetTypeID(bounds) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }
        if rect.origin == .zero && rect.size == .zero { return nil }
        return CGPoint(x: rect.midX, y: primaryHeight - rect.midY)
    }

    private static func frontWindowCenter(pid: pid_t?, primaryHeight: CGFloat) -> CGPoint? {
        guard let pid,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.width > 40, rect.height > 40
            else { continue }
            return CGPoint(x: rect.midX, y: primaryHeight - rect.midY)
        }
        return nil
    }
}
