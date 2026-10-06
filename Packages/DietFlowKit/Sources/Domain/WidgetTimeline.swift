import Foundation

/// One meal as a widget draws it.
public struct WidgetMealItem: Hashable, Identifiable, Sendable {
    public let key: OccurrenceKey
    public let type: MealType
    public let typeLabel: String
    public let date: Date
    public let title: String
    public let summary: String?
    public let calories: Int?
    public let role: MealRole

    public init(occurrence: MealOccurrence, role: MealRole) {
        key = occurrence.key
        type = occurrence.meal.type
        typeLabel = occurrence.meal.typeLabel
        date = occurrence.date
        title = occurrence.meal.title
        summary = occurrence.meal.details?.trimmedNonEmpty
        calories = occurrence.meal.nutrition.calories
        self.role = role
    }

    public var id: OccurrenceKey { key }
}

/// A widget's whole picture at one moment of an active plan.
public struct WidgetDayContent: Hashable, Sendable {
    /// Why `primary` is the meal in front.
    public enum Lead: Hashable, Sendable {
        /// Its time has come.
        case now
        /// Later today.
        case next
        /// Nothing is left today; this is the first meal of `CalendarDay`.
        case laterDay(CalendarDay)
        /// The plan has not begun; it starts on `CalendarDay`.
        case planStarts(CalendarDay)
    }

    public let today: CalendarDay
    public let planName: String
    public let lead: Lead?
    public let primary: WidgetMealItem?
    /// The meal after `primary`.
    public let following: WidgetMealItem?
    /// The day `following` falls on, when that is not the same day as `primary`.
    public let followingDay: CalendarDay?
    /// All of today's meals, in order.
    public let schedule: [WidgetMealItem]
    public let remainingCount: Int
    public let isDayComplete: Bool
    /// Minutes until `primary` when it is next and at most an hour away: drives "in 12 min".
    public let minutesUntilPrimary: Int?
}

public enum WidgetContent: Hashable, Sendable {
    /// No plan has been set up yet.
    case noPlan
    /// The shared file could not be read; opening the app rewrites it.
    case needsRefresh
    /// A plan that does not repeat has run its course.
    case planEnded(planName: String, lastDay: CalendarDay)
    case active(WidgetDayContent)
}

/// A widget timeline entry before WidgetKit gets involved: when, and what to show from then on.
public struct WidgetMoment: Hashable, Sendable {
    public let date: Date
    public let content: WidgetContent

    public init(date: Date, content: WidgetContent) {
        self.date = date
        self.content = content
    }
}

/// Works out, from a snapshot, every moment a widget's face needs to change and what it shows
/// then. WidgetKit plays the moments back on its own, the way the Calendar widget moves from event
/// to event, so the widget stays right without the app running and without constant reloads.
public enum WidgetTimelineBuilder {
    /// The widget asks for a fresh timeline after this long; the moments reach further than this,
    /// so there is never a gap.
    public static let reloadInterval: TimeInterval = 12 * 3600
    public static let horizon: TimeInterval = 36 * 3600
    /// How far ahead of a meal the "in 12 min" countdown starts.
    public static let countdownLead = 60
    public static let countdownStep = 5
    /// The most moments one timeline holds.
    public static let momentLimit = 200

    /// When the widget should ask for a fresh timeline: after `reloadInterval`, or sooner when the
    /// moments end sooner. An ordinary plan's moments reach three times as far as the interval, so
    /// this is the interval. But the moments are capped at `limit`, and if a plan ever filled the
    /// cap before the interval was up, asking again only at the interval would leave the last
    /// moment — "in 5 min", say — on screen for hours.
    public static func reloadDate(after moments: [WidgetMoment], from now: Date, limit: Int = WidgetTimelineBuilder.momentLimit) -> Date {
        let regular = now.addingTimeInterval(reloadInterval)
        guard moments.count >= limit, let last = moments.last else { return regular }
        // Never sooner than a quarter of an hour: WidgetKit budgets reloads.
        return min(regular, max(last.date, now.addingTimeInterval(15 * 60)))
    }

    public static func content(for snapshot: WidgetSnapshot?, at date: Date, timeZone: TimeZone = .current) -> WidgetContent {
        guard let snapshot else { return .noPlan }
        guard snapshot.isReadable else { return .needsRefresh }
        guard let plan = snapshot.plan else { return .noPlan }

        let schedule = MealSchedule(plan: plan, timeZone: timeZone, currentWindow: snapshot.preferences.mealWindow)
        let states = snapshot.occurrenceStates
        let today = CalendarDay(date, in: timeZone)
        let phase = schedule.phase(on: today)
        if case .ended(let lastDay) = phase {
            return .planEnded(planName: plan.name, lastDay: lastDay)
        }

        let agenda = schedule.agenda(on: today, states: states, now: date)
        let focus = schedule.focus(states: states, now: date)

        var lead: WidgetDayContent.Lead?
        var primary: WidgetMealItem?
        var following: WidgetMealItem?
        var followingDay: CalendarDay?
        var minutesUntilPrimary: Int?

        if let focus {
            switch focus.kind {
            case .now:
                lead = .now
            case .next:
                lead = .next
            case .laterDay:
                if case .notStarted(let start) = phase {
                    lead = .planStarts(start)
                } else {
                    lead = .laterDay(focus.occurrence.day)
                }
            }
            let role = agenda.items.first { $0.id == focus.occurrence.key }?.role ?? .upcoming
            primary = WidgetMealItem(occurrence: focus.occurrence, role: role)

            if let next = focus.following {
                let nextRole = agenda.items.first { $0.id == next.key }?.role ?? .upcoming
                following = WidgetMealItem(occurrence: next, role: nextRole)
                followingDay = next.day == focus.occurrence.day ? nil : next.day
            }

            if focus.kind == .next {
                let minutes = Int((focus.occurrence.date.timeIntervalSince(date) / 60).rounded(.up))
                if minutes > 0, minutes <= countdownLead { minutesUntilPrimary = minutes }
            }
        }

        return .active(WidgetDayContent(
            today: today,
            planName: plan.name,
            lead: lead,
            primary: primary,
            following: following,
            followingDay: followingDay,
            schedule: agenda.items.map { WidgetMealItem(occurrence: $0.occurrence, role: $0.role) },
            remainingCount: agenda.remainingCount,
            isDayComplete: agenda.isComplete,
            minutesUntilPrimary: minutesUntilPrimary
        ))
    }

    /// The moments from `now` to `now + horizon`, first one at `now`. Consecutive moments that
    /// would look the same are merged.
    public static func moments(for snapshot: WidgetSnapshot?, from now: Date, timeZone: TimeZone = .current, horizon: TimeInterval = WidgetTimelineBuilder.horizon, limit: Int = WidgetTimelineBuilder.momentLimit) -> [WidgetMoment] {
        var result = [WidgetMoment(date: now, content: content(for: snapshot, at: now, timeZone: timeZone))]
        for date in transitionDates(for: snapshot, from: now, timeZone: timeZone, horizon: horizon) {
            guard result.count < limit else { break }
            let next = content(for: snapshot, at: date, timeZone: timeZone)
            if next != result.last?.content {
                result.append(WidgetMoment(date: date, content: next))
            }
        }
        return result
    }

    /// Every instant after `now`, up to `horizon`, at which the picture can change: midnight,
    /// each meal's time, the end of each meal's "now" window, and the countdown steps before a meal.
    public static func transitionDates(for snapshot: WidgetSnapshot?, from now: Date, timeZone: TimeZone = .current, horizon: TimeInterval = WidgetTimelineBuilder.horizon) -> [Date] {
        guard let snapshot, let plan = snapshot.plan, snapshot.isReadable else { return [] }
        let schedule = MealSchedule(plan: plan, timeZone: timeZone, currentWindow: snapshot.preferences.mealWindow)
        let end = now.addingTimeInterval(horizon)
        let today = CalendarDay(now, in: timeZone)
        let days = Int(horizon / 86_400) + 2

        var dates = Set<Date>()
        for offset in 0...days {
            let day = today.adding(days: offset)
            dates.insert(day.startDate(in: timeZone))
            let occurrences = schedule.occurrences(on: day)
            let dayEnd = day.endDate(in: timeZone)
            for (index, occurrence) in occurrences.enumerated() {
                dates.insert(occurrence.date)
                var windowEnd = min(occurrence.date.addingTimeInterval(schedule.currentWindow), dayEnd)
                if let later = occurrences[(index + 1)...].first(where: { $0.date > occurrence.date }) {
                    windowEnd = min(windowEnd, later.date)
                }
                dates.insert(windowEnd)
                for minutes in stride(from: countdownLead, through: countdownStep, by: -countdownStep) {
                    dates.insert(occurrence.date.addingTimeInterval(TimeInterval(-minutes * 60)))
                }
            }
        }
        return dates.filter { $0 > now && $0 <= end }.sorted()
    }
}
