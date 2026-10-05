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
        MealWidgetEntry.sample()
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (MealWidgetEntry) -> Void) {
        if context.isPreview {
            completion(MealWidgetEntry.sample())
            return
        }
        completion(entries().first ?? MealWidgetEntry.sample())
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<MealWidgetEntry>) -> Void) {
        completion(Timeline(entries: entries(), policy: .after(MealWidgetTimeline.reloadDate())))
    }

    private func entries() -> [MealWidgetEntry] {
        let result = WidgetSnapshotReader().read()
        var isUnreadable = false
        if case .unreadable = result {
            isUnreadable = true
        }
        return MealWidgetTimeline.entries(snapshot: result.snapshot, isUnreadable: isUnreadable)
    }
}

struct NextMealEntryView: View {
    let entry: MealWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        MealWidgetView(entry: entry, family: family) { item in
            Button(intent: MarkMealDoneIntent(meal: MealOccurrenceEntity(item))) {
                WidgetDoneLabel()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(AppColors.brandAccent)
        }
        .modifier(WidgetBackground(family: family))
        // A tap opens the meal the widget is showing; the Done button works without opening the app.
        .widgetURL(link.url)
    }

    private var link: AppLink {
        if case .active(let day) = entry.content, let primary = day.primary {
            return .meal(primary.key)
        }
        return .today
    }
}

/// The system's widget background on the Home Screen; none on the Lock Screen, where the
/// wallpaper shows through.
private struct WidgetBackground: ViewModifier {
    let family: WidgetFamily

    @ViewBuilder
    func body(content: Content) -> some View {
        switch family {
        case .accessoryRectangular, .accessoryInline, .accessoryCircular:
            content.containerBackground(for: .widget) { Color.clear }
        default:
            content.containerBackground(.background, for: .widget)
        }
    }
}

struct NextMealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextMeal", provider: NextMealProvider()) { entry in
            NextMealEntryView(entry: entry)
        }
        .configurationDisplayName(Text("widget.nextMeal.name"))
        .description(Text("widget.nextMeal.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
