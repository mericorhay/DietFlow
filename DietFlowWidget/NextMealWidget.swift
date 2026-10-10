import AppIntents
import SwiftUI
import WidgetKit
import DesignSystem
import Domain
import Persistence
import WidgetUI

/// Reads the snapshot the app wrote and hands WidgetKit every moment the widget changes, up front.
/// No database, no network: one small file and pure functions, so it is fast and the same every time.
struct NextMealProvider: TimelineProvider {
    func placeholder(in context: Context) -> MealWidgetEntry {
        MealWidgetEntry.gallery()
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (MealWidgetEntry) -> Void) {
        let read = WidgetSnapshotReader().read()
        let snapshot = read.snapshot.map(withCurrentSettings)
        // In the gallery: the person's own day when there is one, otherwise the example lunchtime
        // in their colour — never an empty "no plan" card.
        if context.isPreview, snapshot?.plan == nil {
            completion(MealWidgetEntry.gallery(preferences: snapshot?.preferences ?? WidgetPreferences()))
            return
        }
        completion(entries(read, snapshot: snapshot).first ?? MealWidgetEntry.gallery())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<MealWidgetEntry>) -> Void) {
        let read = WidgetSnapshotReader().read()
        let entries = entries(read, snapshot: read.snapshot.map(withCurrentSettings))
        completion(Timeline(entries: entries, policy: .after(MealWidgetTimeline.reloadDate(after: entries))))
    }

    private func entries(_ read: WidgetSnapshotReadResult, snapshot: WidgetSnapshot?) -> [MealWidgetEntry] {
        var isUnreadable = false
        if case .unreadable = read {
            isUnreadable = true
        }
        return MealWidgetTimeline.entries(snapshot: snapshot, isUnreadable: isUnreadable)
    }

    /// Whether a late start can move the day lives in the app's settings, which this process can
    /// read too; taking it from there means "I'm up" is never offered while the person has smart
    /// meal times switched off, whatever version of the app wrote the snapshot.
    private func withCurrentSettings(_ snapshot: WidgetSnapshot) -> WidgetSnapshot {
        var updated = snapshot
        updated.preferences.smartMealTimes = AppSettingsStore.load().smartMealTimes
        return updated
    }
}

struct MealWidgetEntryView: View {
    let entry: MealWidgetEntry
    let kind: MealWidgetKind
    @Environment(\.widgetFamily) private var family

    var body: some View {
        MealWidgetView(entry: entry, kind: kind, family: family) { action, label in
            switch action {
            case .markEaten(let item):
                Button(intent: MarkMealDoneIntent(meal: MealOccurrenceEntity(item))) {
                    label
                }
                .buttonStyle(.plain)
            case .unmark(let item):
                Button(intent: UnmarkMealIntent(meal: MealOccurrenceEntity(item))) {
                    label
                }
                .buttonStyle(.plain)
            case .startDay:
                Button(intent: WidgetStartDayIntent()) {
                    label
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.widgetRendering, .widget)
        .modifier(WidgetBackground(family: family, preferences: entry.preferences))
        // A tap anywhere else opens what the widget is showing; its buttons work without opening
        // the app, and on medium and large each row opens its own meal.
        .widgetURL(link.url)
    }

    private var link: AppLink {
        switch entry.content {
        case .noPlan:
            return .importPlan
        case .planEnded:
            return .plan
        case .active(let day):
            if let primary = day.primary {
                return .meal(primary.key)
            }
            return .today
        case .needsRefresh:
            return .today
        }
    }
}

/// The colour and tone chosen on the Widgets tab on the Home Screen; nothing on the Lock Screen,
/// where the wallpaper shows through.
private struct WidgetBackground: ViewModifier {
    let family: WidgetFamily
    let preferences: WidgetPreferences

    @ViewBuilder
    func body(content: Content) -> some View {
        switch family {
        case .accessoryRectangular, .accessoryInline, .accessoryCircular:
            content.containerBackground(for: .widget) { Color.clear }
        default:
            content.containerBackground(for: .widget) { WidgetThemeBackground(preferences) }
        }
    }
}

/// What to eat now or next. The widget most people add.
struct NextMealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MealWidgetKind.nextMeal.rawValue, provider: NextMealProvider()) { entry in
            MealWidgetEntryView(entry: entry, kind: .nextMeal)
        }
        .configurationDisplayName(Text("widget.nextMeal.name"))
        .description(Text("widget.nextMeal.description"))
        .supportedFamilies(MealWidgetKind.nextMeal.families)
    }
}

/// The whole day as a list.
struct TodayMealsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MealWidgetKind.today.rawValue, provider: NextMealProvider()) { entry in
            MealWidgetEntryView(entry: entry, kind: .today)
        }
        .configurationDisplayName(Text("widget.today.name"))
        .description(Text("widget.today.description"))
        .supportedFamilies(MealWidgetKind.today.families)
    }
}

/// How far through the day's meals the person is.
struct DayProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MealWidgetKind.progress.rawValue, provider: NextMealProvider()) { entry in
            MealWidgetEntryView(entry: entry, kind: .progress)
        }
        .configurationDisplayName(Text("widget.progress.name"))
        .description(Text("widget.progress.description"))
        .supportedFamilies(MealWidgetKind.progress.families)
    }
}
