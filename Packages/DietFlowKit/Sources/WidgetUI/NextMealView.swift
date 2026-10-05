import Foundation
import SwiftUI
import Domain

/// Placeholder layout: the time, the meal and what is in it. The real design replaces the body;
/// the entry it draws from stays the same.
public struct NextMealView: View {
    private let entry: NextMealEntry

    public init(entry: NextMealEntry) {
        self.entry = entry
    }

    public var body: some View {
        if let scheduled = entry.meal {
            VStack(alignment: .leading, spacing: 4) {
                Text(scheduled.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(scheduled.meal.title)
                    .font(.headline)
                ForEach(scheduled.meal.items, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text("widget.nextMeal.empty", bundle: .module)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
