import Foundation
import OSLog
import Domain

private let logger = Logger(subsystem: "com.orhay.dietflow", category: "SharedFiles")

/// Where the widget snapshot lives: the App Group container, the one place both processes reach.
public enum WidgetSnapshotLocation {
    public static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("widget-snapshot.json", isDirectory: false)
    }
}

/// Writes the widget's snapshot. Called by the app, and by an intent run from the widget, after
/// anything the widget shows has changed; the caller then asks WidgetKit to reload.
public struct WidgetSnapshotWriter: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Nil when the App Group is not available to this build.
    public static func shared() -> WidgetSnapshotWriter? {
        WidgetSnapshotLocation.fileURL.map(WidgetSnapshotWriter.init(fileURL:))
    }

    public func write(_ snapshot: WidgetSnapshot) throws {
        try snapshot.encoded().write(to: fileURL, options: [.atomic])
    }
}

public enum WidgetSnapshotReadResult: Sendable {
    /// Nothing written yet: the app has not run since it was installed.
    case missing
    /// Written, but not readable as a snapshot.
    case unreadable
    case snapshot(WidgetSnapshot)

    public var snapshot: WidgetSnapshot? {
        if case .snapshot(let value) = self { return value }
        return nil
    }
}

/// Reads the widget's snapshot. Fast and side-effect free: the widget calls it for every timeline.
public struct WidgetSnapshotReader: Sendable {
    public let fileURL: URL?

    public init(fileURL: URL? = WidgetSnapshotLocation.fileURL) {
        self.fileURL = fileURL
    }

    public func read() -> WidgetSnapshotReadResult {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return .missing }
        do {
            return .snapshot(try WidgetSnapshot.decode(data))
        } catch {
            logger.error("Widget snapshot unreadable: \(String(describing: error), privacy: .public)")
            return .unreadable
        }
    }
}

public enum AppSettingsStore {
    private static let key = "appSettings.v1"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    }

    public static func load() -> AppSettings {
        guard let data = defaults.data(forKey: key), let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    public static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// A plan handed over by the Import Plan shortcut, waiting for the app to show it for review.
public enum PendingImportInbox {
    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("pending-import.txt", isDirectory: false)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("pending-import.txt", isDirectory: false)
    }

    public static func put(_ text: String) throws {
        guard let fileURL else { return }
        try Data(text.utf8).write(to: fileURL, options: [.atomic])
    }

    /// The waiting text, removed so it is shown once.
    public static func take() -> String? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        try? FileManager.default.removeItem(at: fileURL)
        return String(data: data, encoding: .utf8)?.trimmedNonEmpty
    }
}
