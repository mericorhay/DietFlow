import SwiftUI
import WidgetKit
import Persistence
import WidgetUI

/// Reads the plan the app saved and hands WidgetKit the day's entries. Everything worth testing
/// is in WidgetUI; this file only connects it to the extension.
struct NextMealProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextMealEntry {
        NextMealEntry(date: .now, meal: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (NextMealEntry) -> Void) {
        completion(entries().first ?? NextMealEntry(date: .now, meal: nil))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<NextMealEntry>) -> Void) {
        completion(Timeline(entries: entries(), policy: .atEnd))
    }

    private func entries() -> [NextMealEntry] {
        NextMealTimeline.entries(from: PlanStore.shared()?.load())
    }
}

struct NextMealWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextMeal", provider: NextMealProvider()) { entry in
            NextMealView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(Text("widget.nextMeal.name"))
        .description(Text("widget.nextMeal.description"))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
