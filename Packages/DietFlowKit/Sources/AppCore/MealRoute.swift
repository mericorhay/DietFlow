import Foundation
import Domain

/// Where a screen sends the person for a meal: one meal on one day.
public enum MealRoute: Hashable, Sendable {
    case occurrence(OccurrenceKey)
}
