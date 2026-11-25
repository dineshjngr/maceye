import Combine
import Foundation

/// Optional settings sync between your Macs.
/// It writes one small JSON file into your own iCloud Drive folder and lets macOS sync it.
/// The app itself never opens a network connection. Off by default.
final class SettingsSync: ObservableObject {
    static let shared = SettingsSync()

    @Published private(set) var status = "Off"

    private var enabled = false
    private var timer: Timer?
    private var lastSynced: Config?
    private var lastModified: Date?
    private var pendingPush: DispatchWorkItem?

    private init() {}

    private var folderURL: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("MacEye", isDirectory: true)
    }

    private var fileURL: URL? { folderURL?.appendingPathComponent("settings.json") }

    /// Settings that belong to this Mac only are left out of the synced file.
    private func payload(_ config: Config) -> Config {
        var copy = config
        copy.floatingPositions = [:]
        copy.iCloudDriveSync = false
        copy.eyesHidden = false
        return copy
    }

    func configChanged(_ config: Config) {
        if config.iCloudDriveSync != enabled {
            enabled = config.iCloudDriveSync
            if enabled { start(config) } else { stop() }
            return
        }
        guard enabled else { return }
        let new = payload(config)
        guard new != lastSynced else { return }
        pendingPush?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.push(new) }
        pendingPush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func start(_ config: Config) {
        guard let fileURL else {
            status = "iCloud Drive is not turned on for this Mac"
            return
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            lastSynced = payload(config)
            DispatchQueue.main.async { [weak self] in self?.pull(force: true) }
        } else {
            push(payload(config))
        }
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.pull(force: false) }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        pendingPush?.cancel()
        lastSynced = nil
        lastModified = nil
        status = "Off"
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func push(_ config: Config) {
        guard enabled, let folderURL, let fileURL, let data = config.encoded() else { return }
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lastSynced = config
            lastModified = modificationDate(fileURL)
            status = "Synced through iCloud Drive"
        } catch {
            status = "Could not write to iCloud Drive: \(error.localizedDescription)"
        }
    }

    private func pull(force: Bool) {
        guard enabled, let fileURL else { return }
        guard let modified = modificationDate(fileURL) else { return }
        if !force, let lastModified, modified <= lastModified { return }
        lastModified = modified
        guard let data = try? Data(contentsOf: fileURL), let remote = Config.decode(data) else { return }
        let remotePayload = payload(remote)
        guard remotePayload != lastSynced else {
            status = "Synced through iCloud Drive"
            return
        }
        lastSynced = remotePayload
        let local = ConfigStore.shared.config
        var merged = remotePayload
        merged.floatingPositions = local.floatingPositions
        merged.iCloudDriveSync = local.iCloudDriveSync
        merged.eyesHidden = local.eyesHidden
        ConfigStore.shared.config = merged
        status = "Synced through iCloud Drive"
    }
}
