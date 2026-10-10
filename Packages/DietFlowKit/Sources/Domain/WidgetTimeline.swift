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
    /// The energy figure is the assistant's estimate, not the plan's: it is always drawn with "≈".
    public let isEstimated: Bool
    /// How many minutes later than the plan's own time this meal is today, because the day started
    /// late (`DayStart`): the widget's "+45 min" chip. 0 when it keeps its time.
    public let shiftMinutes: Int

    public init(occurrence: MealOccurrence, role: MealRole) {
        key = occurrence.key
        type = occurrence.meal.type
        typeLabel = occurrence.meal.typeLabel
        date = occurrence.date
        title = occurrence.meal.title
        summary = occurrence.meal.details?.trimmedNonEmpty
        calories = occurrence.meal.nutrition.calories
        isEstimated = occurrence.meal.nutrition.isEstimated
        shiftMinutes = max(0, occurrence.time.minutesSinceMidnight - occurrence.meal.time.minutesSinceMidnight)
        self.role = role
    }

    public var id: OccurrenceKey { key }

    /// The energy as `EnergyUnit.format(_:)` wants it, so an estimate keeps its "≈".
    public var nutrition: Nutrition {
        Nutrition(calories: calories, estimated: isEstimated)
    }

    /// The meal was moved later today by a late start.
    public var isMoved: Bool { shiftMinutes > 0 }

    /// The foods of a title written as a list ("2 eggs, 5 olives, 1 slice of cheese"), for drawing
    /// as a plate; empty when the title reads as one dish.
    public var plateItems: [String] { WidgetPlate.items(in: title) }
}

/// Dietitians often write a meal as the foods on the plate rather than as a dish. A title like that
/// reads better as a short list than as one long, wrapped line.
public enum WidgetPlate {
    /// Fewer parts than this is a dish with a comma in its name ("Feta, cucumber and walnut salad").
    public static let minimumItems = 3
    /// A part longer than this is a sentence, not a food.
    public static let longestItem = 32

    /// The parts of `title` when it is a list of foods; empty otherwise. Split on commas,
    /// semicolons, plus signs, bullets and line breaks — but not on a decimal comma ("1,5 dilim"),
    /// which Turkish and Spanish write — with a leading "and", "ve" or "y" taken off each part.
    public static func items(in title: String) -> [String] {
        var parts: [String] = []
        var current = ""
        let characters = Array(title)
        for (index, character) in characters.enumerated() {
            let isSeparator: Bool
            switch character {
            case ";", "+", "•", "·", "\n":
                isSeparator = true
            case ",":
                let before = index > 0 ? characters[index - 1] : " "
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                isSeparator = !(before.isNumber && after.isNumber)
            default:
                isSeparator = false
            }
            if isSeparator {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)

        let items = parts.compactMap { part -> String? in
            var text = part.trimmingCharacters(in: .whitespacesAndNewlines)
            for conjunction in ["and ", "ve ", "y ", "e ", "& ", "ile "] where text.lowercased().hasPrefix(conjunction) {
                text = String(text.dropFirst(conjunction.count)).trimmingCharacters(in: .whitespaces)
                break
            }
            return text.isEmpty ? nil : text
        }
        guard items.count >= minimumItems, items.allSatisfy({ $0.count <= longestItem }) else { return [] }
        return items
    }
}

/// What today's meals add up to, for the "≈ 820 of 1,640 kcal" line: only meals whose energy is
/// known count, and the whole is an estimate when any part of it is.
public struct WidgetEnergy: Hashable, Sendable {
    /// Kilocalories of the meals marked eaten.
    public let eaten: Int
    /// Kilocalories of every meal planned today, eaten or not.
    public let planned: Int
    public let isEstimated: Bool

    public init(eaten: Int, planned: Int, isEstimated: Bool) {
        self.eaten = eaten
        self.planned = planned
        self.isEstimated = isEstimated
    }

    public var fraction: Double {
        planned > 0 ? min(Double(eaten) / Double(planned), 1) : 0
    }
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
    /// Minutes until `primary`, at the moment this picture describes, when it is next and at most
    /// `WidgetTimelineBuilder.countdownLead` away. The widget draws the countdown itself, live
    /// (`Text(_:style: .relative)`), so this only says that the meal is close.
    public let minutesUntilPrimary: Int?
    /// While `primary` is on now: when it gives way to the next meal (its window, cut short by the
    /// next meal or by midnight). The "until 14:30" bar runs out at this moment.
    public let primaryEnds: Date?
    /// While `primary` is still ahead: when the wait for it began — the meal before it, or the start
    /// of the morning — so a ring can empty from then until it.
    public let waitStarted: Date?
    /// The plan day `today` is, zero-based, and how many days the plan has: "Day 3 of 14". Nil
    /// before the plan starts.
    public let dayIndex: Int?
    public let dayCount: Int
    /// The widget offers "I'm up": it is morning (from 05:00), smart meal times are on, today has
    /// meals, none of them is marked yet, the day has not been started, and the first meal is not
    /// yet so far behind that a late start would no longer be inferred (`WidgetTimelineBuilder
    /// .startDayOfferLength`).
    public let offersStartDay: Bool

    /// `primary` is next and close: the countdown is worth showing in front.
    public var isSoon: Bool { minutesUntilPrimary != nil }

    /// The first meal of the next day with meals, when nothing is left today: the bottom line of a
    /// finished day.
    public var nextDayFirst: WidgetMealItem? {
        if case .laterDay = lead { return primary }
        return followingDay != nil ? following : nil
    }

    /// Today's energy, or nil when no meal today has a figure.
    public var energy: WidgetEnergy? {
        let known = schedule.filter { $0.calories != nil }
        guard !known.isEmpty else { return nil }
        let planned = known.reduce(0) { $0 + ($1.calories ?? 0) }
        let eaten = known.filter { $0.role == .done }.reduce(0) { $0 + ($1.calories ?? 0) }
        return WidgetEnergy(eaten: eaten, planned: planned, isEstimated: known.contains(where: \.isEstimated))
    }
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

/// A widget timeline entry before WidgetKit gets involved: when, what to show from then on, and
/// how much it matters to put this widget on top of a Smart Stack then.
public struct WidgetMoment: Hashable, Sendable {
    public let date: Date
    public let content: WidgetContent
    /// 0–100, for `TimelineEntryRelevance`: see `WidgetTimelineBuilder.relevance(of:at:)`.
    public let relevance: Double

    public init(date: Date, content: WidgetContent, relevance: Double = 0) {
        self.date = date
        self.content = content
        self.relevance = relevance
    }
}

/// Works out, from a snapshot, every moment a widget's face needs to change and what it shows
/// then. WidgetKit plays the moments back on its own, the way the Calendar widget moves from event
/// to event, so the widget stays right without the app running and without constant reloads.
///
/// Countdowns are not moments: the widget draws them with WidgetKit's own live text and progress
/// views, which tick by themselves to the second. So a day needs only a handful of moments per
/// meal, not one every five minutes.
public enum WidgetTimelineBuilder {
    /// The widget asks for a fresh timeline after this long; the moments reach further than this,
    /// so there is never a gap.
    public static let reloadInterval: TimeInterval = 12 * 3600
    public static let horizon: TimeInterval = 36 * 3600
    /// How far ahead of a meal, in minutes, it counts as soon: the countdown moves to the front.
    public static let countdownLead = 60
    /// How far ahead of a meal, in minutes, the widget asks to be on top of a Smart Stack.
    public static let relevanceLead = 15
    /// The most moments one timeline holds.
    public static let momentLimit = 200
    /// "I'm up" is offered from this time of day, in minutes after midnight (05:00)…
    public static let startDayOfferOpens = 5 * 60
    /// …until this long after the day's first meal: by then a late start is no longer inferred
    /// from the first meal either (`MealPlanStore`), and the morning is over.
    public static let startDayOfferLength: TimeInterval = 4 * 3600

    /// Relevance scores for `TimelineEntryRelevance`.
    public enum Relevance {
        /// From `relevanceLead` minutes before a meal until it gives way to the next.
        public static let mealtime: Double = 100
        /// Every meal of the day is marked.
        public static let dayComplete: Double = 30
        /// Any other time of an active plan.
        public static let ordinary: Double = 10
        /// No plan, an unreadable file or a finished plan: nothing worth rising for.
        public static let none: Double = 0
    }

    /// When the widget should ask for a fresh timeline: after `reloadInterval`, or sooner when the
    /// moments end sooner. An ordinary plan's moments reach three times as far as the interval, so
    /// this is the interval. But the moments are capped at `limit`, and if a plan ever filled the
    /// cap before the interval was up, asking again only at the interval would leave the last
    /// moment on screen for hours.
    public static func reloadDate(after moments: [WidgetMoment], from now: Date, limit: Int = WidgetTimelineBuilder.momentLimit) -> Date {
        let regular = now.addingTimeInterval(reloadInterval)
        guard moments.count >= limit, let last = moments.last else { return regular }
        // Never sooner than a quarter of an hour: WidgetKit budgets reloads.
        return min(regular, max(last.date, now.addingTimeInterval(15 * 60)))
    }

    /// How much it matters, at `date`, that this widget is the one showing in a Smart Stack.
    public static func relevance(of content: WidgetContent, at date: Date) -> Double {
        guard case .active(let day) = content, let primary = day.primary else { return Relevance.none }
        switch day.lead {
        case .now?:
            return Relevance.mealtime
        case .next? where primary.date.timeIntervalSince(date) <= TimeInterval(relevanceLead * 60):
            return Relevance.mealtime
        default:
            return day.isDayComplete ? Relevance.dayComplete : Relevance.ordinary
        }
    }

    public static func content(for snapshot: WidgetSnapshot?, at date: Date, timeZone: TimeZone = .current) -> WidgetContent {
        guard let snapshot else { return .noPlan }
        guard snapshot.isReadable else { return .needsRefresh }
        guard let plan = snapshot.plan else { return .noPlan }

        let dayStarts = snapshot.recordedDayStarts
        let schedule = MealSchedule(plan: plan, timeZone: timeZone, currentWindow: snapshot.preferences.mealWindow, dayStarts: dayStarts)
        let states = snapshot.occurrenceStates
        let today = CalendarDay(date, in: timeZone)
        let phase = schedule.phase(on: today)
        if case .ended(let lastDay) = phase {
            return .planEnded(planName: plan.name, lastDay: lastDay)
        }

        let agenda = schedule.agenda(on: today, states: states, now: date)
        let focus = schedule.focus(states: states, now: date)
        let todays = agenda.items.map(\.occurrence)

        var lead: WidgetDayContent.Lead?
        var primary: WidgetMealItem?
        var following: WidgetMealItem?
        var followingDay: CalendarDay?
        var minutesUntilPrimary: Int?
        var primaryEnds: Date?
        var waitStarted: Date?

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

            if focus.kind == .now {
                primaryEnds = windowEnd(of: focus.occurrence, among: todays, schedule: schedule)
            } else {
                waitStarted = waitStart(for: focus.occurrence, today: today, todays: todays, timeZone: timeZone)
            }
        }

        var dayIndex: Int?
        if case .active(let index, _) = phase { dayIndex = index }

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
            minutesUntilPrimary: minutesUntilPrimary,
            primaryEnds: primaryEnds,
            waitStarted: waitStarted,
            dayIndex: dayIndex,
            dayCount: plan.schedule.length,
            offersStartDay: offersStartDay(snapshot: snapshot, todays: todays, today: today, at: date, timeZone: timeZone)
        ))
    }

    /// When a meal that is on now gives way: its window, but not into the next meal or the next day.
    /// The same rule `MealSchedule.agenda` uses to decide it is current.
    static func windowEnd(of occurrence: MealOccurrence, among todays: [MealOccurrence], schedule: MealSchedule) -> Date {
        var end = min(occurrence.date.addingTimeInterval(schedule.currentWindow), occurrence.day.endDate(in: schedule.timeZone))
        if let later = todays.first(where: { $0.date > occurrence.date }) {
            end = min(end, later.date)
        }
        return end
    }

    /// When the wait for `occurrence` began: the latest meal before it today, else the morning
    /// (05:00) when that is before it, else the start of today.
    static func waitStart(for occurrence: MealOccurrence, today: CalendarDay, todays: [MealOccurrence], timeZone: TimeZone) -> Date {
        if let previous = todays.last(where: { $0.date < occurrence.date }) {
            return previous.date
        }
        let morning = TimeOfDay(minutesSinceMidnight: startDayOfferOpens).date(on: today, in: timeZone)
        return morning < occurrence.date ? morning : today.startDate(in: timeZone)
    }

    static func offersStartDay(snapshot: WidgetSnapshot, todays: [MealOccurrence], today: CalendarDay, at date: Date, timeZone: TimeZone) -> Bool {
        guard snapshot.preferences.smartMealTimes,
              snapshot.recordedDayStarts[today] == nil,
              let first = todays.first,
              todays.allSatisfy(\.isPending)
        else { return false }
        let opens = TimeOfDay(minutesSinceMidnight: startDayOfferOpens).date(on: today, in: timeZone)
        return date >= opens && date < first.date.addingTimeInterval(startDayOfferLength)
    }

    /// The moments from `now` to `now + horizon`, first one at `now`. Consecutive moments that
    /// would look the same and matter the same are merged.
    public static func moments(for snapshot: WidgetSnapshot?, from now: Date, timeZone: TimeZone = .current, horizon: TimeInterval = WidgetTimelineBuilder.horizon, limit: Int = WidgetTimelineBuilder.momentLimit) -> [WidgetMoment] {
        let first = content(for: snapshot, at: now, timeZone: timeZone)
        var result = [WidgetMoment(date: now, content: first, relevance: relevance(of: first, at: now))]
        for date in transitionDates(for: snapshot, from: now, timeZone: timeZone, horizon: horizon) {
            guard result.count < limit else { break }
            let next = content(for: snapshot, at: date, timeZone: timeZone)
            let score = relevance(of: next, at: date)
            if next != result.last?.content || score != result.last?.relevance {
                result.append(WidgetMoment(date: date, content: next, relevance: score))
            }
        }
        return result
    }

    /// Every instant after `now`, up to `horizon`, at which the picture can change: midnight, the
    /// morning's "I'm up" opening and closing, and for each meal the hour before it (soon), the
    /// quarter of an hour before it (Smart Stack), its time and the end of its "now" window.
    public static func transitionDates(for snapshot: WidgetSnapshot?, from now: Date, timeZone: TimeZone = .current, horizon: TimeInterval = WidgetTimelineBuilder.horizon) -> [Date] {
        guard let snapshot, let plan = snapshot.plan, snapshot.isReadable else { return [] }
        let schedule = MealSchedule(plan: plan, timeZone: timeZone, currentWindow: snapshot.preferences.mealWindow, dayStarts: snapshot.recordedDayStarts)
        let end = now.addingTimeInterval(horizon)
        let today = CalendarDay(now, in: timeZone)
        let days = Int(horizon / 86_400) + 2

        var dates = Set<Date>()
        for offset in 0...days {
            let day = today.adding(days: offset)
            dates.insert(day.startDate(in: timeZone))
            let occurrences = schedule.occurrences(on: day)
            if let first = occurrences.first {
                dates.insert(TimeOfDay(minutesSinceMidnight: startDayOfferOpens).date(on: day, in: timeZone))
                dates.insert(first.date.addingTimeInterval(startDayOfferLength))
            }
            for occurrence in occurrences {
                dates.insert(occurrence.date.addingTimeInterval(TimeInterval(-countdownLead * 60)))
                dates.insert(occurrence.date.addingTimeInterval(TimeInterval(-relevanceLead * 60)))
                dates.insert(occurrence.date)
                dates.insert(windowEnd(of: occurrence, among: occurrences, schedule: schedule))
            }
        }
        return dates.filter { $0 > now && $0 <= end }.sorted()
    }
}
