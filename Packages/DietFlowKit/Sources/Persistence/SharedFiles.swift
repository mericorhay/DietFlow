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

/// Days that started late (`DayStart`), by plan and day, in the App Group's defaults: the widget's
/// process can record one — a first meal marked done late from the widget — and both processes read
/// the same. Small and short-lived, so a day is kept only a couple of weeks.
@MainActor
public final class DayStartStore {
    private static let key = "dayStarts.v1"
    /// Days before today that are still kept: the Today screen pages back a little.
    public static let keptDays = 14

    private let defaults: UserDefaults?
    /// Plan id → day → start, when nothing is to be stored (previews and seeded test states).
    private var memory: [String: [String: DayStart]] = [:]

    /// `inMemory` keeps everything in this object and touches nothing on disk.
    public init(inMemory: Bool = false) {
        defaults = inMemory ? nil : (UserDefaults(suiteName: AppGroup.identifier) ?? .standard)
    }

    public func starts(planID: UUID) -> DayStarts {
        var result: DayStarts = [:]
        for (text, start) in read()[planID.uuidString] ?? [:] {
            if let day = CalendarDay(text) { result[day] = start }
        }
        return result
    }

    /// Records where `day` started, or forgets it when `start` is nil. Days older than `keptDays`
    /// are dropped on the way.
    public func set(_ start: DayStart?, on day: CalendarDay, planID: UUID, today: CalendarDay = .today()) {
        var all = read()
        var days = all[planID.uuidString] ?? [:]
        days[day.description] = start
        let earliest = today.adding(days: -Self.keptDays)
        days = days.filter { CalendarDay($0.key).map { $0 >= earliest } ?? false }
        all[planID.uuidString] = days.isEmpty ? nil : days
        write(all)
    }

    public func removePlan(_ planID: UUID) {
        var all = read()
        all[planID.uuidString] = nil
        write(all)
    }

    public func removeAll() {
        write([:])
    }

    private func read() -> [String: [String: DayStart]] {
        guard let defaults else { return memory }
        guard let data = defaults.data(forKey: Self.key), let all = try? JSONDecoder().decode([String: [String: DayStart]].self, from: data) else {
            return [:]
        }
        return all
    }

    private func write(_ all: [String: [String: DayStart]]) {
        guard let defaults else {
            memory = all
            return
        }
        if all.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

public enum PendingImportError: Error, Sendable {
    case tooLong
}

/// A plan handed over by the Import Plan shortcut, waiting for the app to show it for review.
public enum PendingImportInbox {
    private static var fileURL: URL? {
        AppGroup.containerURL?.appendingPathComponent("pending-import.txt", isDirectory: false)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("pending-import.txt", isDirectory: false)
    }

    public static func put(_ text: String) throws {
        // A Shortcut can pass anything. Text longer than Import reads is refused here, so the
        // Shortcut fails where the person can see it instead of the app opening on an error.
        guard text.count <= PlanLimits.importTextLength else { throw PendingImportError.tooLong }
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
