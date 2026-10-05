import Foundation
import WidgetKit
import Domain

/// One timeline entry: from `date` on, the widget shows `content`.
public struct MealWidgetEntry: TimelineEntry, Sendable {
    public let date: Date
    public let content: WidgetContent
    public let preferences: WidgetPreferences

    public init(date: Date, content: WidgetContent, preferences: WidgetPreferences) {
        self.date = date
        self.content = content
        self.preferences = preferences
    }

    /// The sample plan on its first day: the widget gallery and the placeholder.
    public static func sample(now: Date = .now, preferences: WidgetPreferences = WidgetPreferences()) -> MealWidgetEntry {
        let snapshot = WidgetSnapshot.sample(now: now, preferences: preferences)
        return MealWidgetEntry(date: now, content: WidgetTimelineBuilder.content(for: snapshot, at: now), preferences: preferences)
    }

    /// The entry for `now` from a snapshot, for previews inside the app.
    public static func current(for snapshot: WidgetSnapshot?, now: Date = .now) -> MealWidgetEntry {
        MealWidgetEntry(date: now, content: WidgetTimelineBuilder.content(for: snapshot, at: now), preferences: snapshot?.preferences ?? WidgetPreferences())
    }
}

/// Turns the shared snapshot into WidgetKit entries. The widget extension reads the file and calls
/// this; everything about what to show when is decided in `WidgetTimelineBuilder`, where it is tested.
public enum MealWidgetTimeline {
    public static func entries(snapshot: WidgetSnapshot?, isUnreadable: Bool, now: Date = .now, timeZone: TimeZone = .current) -> [MealWidgetEntry] {
        let preferences = snapshot?.preferences ?? WidgetPreferences()
        if isUnreadable {
            return [MealWidgetEntry(date: now, content: .needsRefresh, preferences: preferences)]
        }
        return WidgetTimelineBuilder.moments(for: snapshot, from: now, timeZone: timeZone).map {
            MealWidgetEntry(date: $0.date, content: $0.content, preferences: preferences)
        }
    }

    /// When WidgetKit should ask for a fresh timeline. The entries reach well past it.
    public static func reloadDate(from now: Date = .now) -> Date {
        now.addingTimeInterval(WidgetTimelineBuilder.reloadInterval)
    }
}
