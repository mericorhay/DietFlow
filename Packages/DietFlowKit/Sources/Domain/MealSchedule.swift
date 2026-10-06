import Foundation

/// Where a plan stands on a given day.
public enum PlanPhase: Hashable, Sendable {
    case notStarted(startsOn: CalendarDay)
    /// `dayIndex` is zero-based; `pass` counts how many times the plan has started over.
    case active(dayIndex: Int, pass: Int)
    case ended(lastDay: CalendarDay)
}

/// Turns a plan into meals on real days. The widget, the Today screen, the reminders and the
/// intents all ask this one type, so they cannot disagree about what comes next.
///
/// Days are wall-calendar days and meal times are wall-clock times, so the schedule follows the
/// person: after a flight, lunch is still at 14:00 local time. Only `timeZone` turns them into
/// instants.
public struct MealSchedule: Sendable {
    public let plan: MealPlan
    public let timeZone: TimeZone
    private let mealsByDayIndex: [Int: [Meal]]

    /// How long a meal stays in front after its time when the person has not chosen otherwise.
    public static let defaultWindow: TimeInterval = 60 * 60

    /// How long a meal stays "now" after its time, unless the next meal starts sooner. When it is
    /// over the meal simply gives way to the next one: nothing has to be marked for the day to
    /// move on.
    public let currentWindow: TimeInterval

    public init(plan: MealPlan, timeZone: TimeZone = .current, currentWindow: TimeInterval = MealSchedule.defaultWindow) {
        self.plan = plan
        self.timeZone = timeZone
        self.currentWindow = max(60, currentWindow)
        var grouped: [Int: [Meal]] = [:]
        for meal in plan.meals where meal.dayIndex < plan.schedule.length {
            grouped[meal.dayIndex, default: []].append(meal)
        }
        mealsByDayIndex = grouped.mapValues { $0.sorted(by: Meal.scheduleOrder) }
    }

    // MARK: Days

    public func phase(on day: CalendarDay) -> PlanPhase {
        let schedule = plan.schedule
        let offset = schedule.startDay.days(to: day)
        if offset < 0 {
            return .notStarted(startsOn: schedule.startDay)
        }
        if schedule.repeats {
            return .active(dayIndex: offset % schedule.length, pass: offset / schedule.length)
        }
        if offset < schedule.length {
            return .active(dayIndex: offset, pass: 0)
        }
        return .ended(lastDay: schedule.startDay.adding(days: schedule.length - 1))
    }

    /// The plan day that falls on `day`, or nil before the start or after the end.
    public func dayIndex(on day: CalendarDay) -> Int? {
        if case .active(let index, _) = phase(on: day) { return index }
        return nil
    }

    /// The calendar day that plan day `index` next falls on, on or after `reference`. A plan that
    /// does not repeat has one date per day, past or not.
    public func calendarDay(forDayIndex index: Int, onOrAfter reference: CalendarDay) -> CalendarDay {
        let schedule = plan.schedule
        let first = schedule.startDay.adding(days: index)
        guard schedule.repeats, reference > first else { return first }
        let passes = (first.days(to: reference) + schedule.length - 1) / schedule.length
        return first.adding(days: passes * schedule.length)
    }

    /// The first day after `day` that has at least one meal, looking at most `limit` days ahead.
    public func nextDayWithMeals(after day: CalendarDay, within limit: Int = 62) -> CalendarDay? {
        guard !mealsByDayIndex.isEmpty else { return nil }
        var candidate = day.adding(days: 1)
        if candidate < plan.schedule.startDay {
            candidate = plan.schedule.startDay
        }
        for _ in 0..<max(limit, 1) {
            switch phase(on: candidate) {
            case .ended:
                return nil
            case .notStarted:
                break
            case .active(let index, _):
                if let meals = mealsByDayIndex[index], !meals.isEmpty { return candidate }
            }
            candidate = candidate.adding(days: 1)
        }
        return nil
    }

    // MARK: Meals

    /// The meals of plan day `index`, in clock order.
    public func meals(onDayIndex index: Int) -> [Meal] {
        mealsByDayIndex[index] ?? []
    }

    /// The meals scheduled on `day`, in clock order. Empty before the start and after the end.
    public func meals(on day: CalendarDay) -> [Meal] {
        guard let index = dayIndex(on: day) else { return [] }
        return meals(onDayIndex: index)
    }

    public func occurrences(on day: CalendarDay, states: OccurrenceStates = [:]) -> [MealOccurrence] {
        meals(on: day).map { meal in
            let key = OccurrenceKey(mealID: meal.id, day: day)
            return MealOccurrence(meal: meal, day: day, date: meal.time.date(on: day, in: timeZone), state: states[key] ?? .pending)
        }
    }

    /// The occurrence `key` names, if that meal really is scheduled on that day.
    public func occurrence(for key: OccurrenceKey, states: OccurrenceStates = [:]) -> MealOccurrence? {
        occurrences(on: key.day, states: states).first { $0.meal.id == key.mealID }
    }

    /// Every occurrence from the start of `first` for `days` days, in time order.
    public func occurrences(from first: CalendarDay, days: Int, states: OccurrenceStates = [:]) -> [MealOccurrence] {
        (0..<max(days, 0)).flatMap { occurrences(on: first.adding(days: $0), states: states) }
    }

    // MARK: Now and next

    /// Each of `day`'s meals with its role at `now`: done, skipped, current, next, upcoming or past.
    public func agenda(on day: CalendarDay, states: OccurrenceStates = [:], now: Date) -> DayAgenda {
        let occurrences = occurrences(on: day, states: states)
        let today = CalendarDay(now, in: timeZone)
        let dayEnd = day.endDate(in: timeZone)

        var roles: [MealRole] = occurrences.indices.map { index in
            let occurrence = occurrences[index]
            switch occurrence.state {
            case .completed:
                return .done
            case .skipped:
                return .skipped
            case .pending:
                if day < today { return .past }
                if day > today || occurrence.date > now { return .upcoming }
                // Its time has come. It stays current for a while, but not into the next meal.
                var windowEnd = min(occurrence.date.addingTimeInterval(currentWindow), dayEnd)
                if let later = occurrences[(index + 1)...].first(where: { $0.date > occurrence.date }) {
                    windowEnd = min(windowEnd, later.date)
                }
                return now < windowEnd ? .current : .past
            }
        }
        if day == today, !roles.contains(.current), let first = roles.firstIndex(of: .upcoming) {
            roles[first] = .next
        }

        let items = zip(occurrences, roles).map { AgendaItem(occurrence: $0, role: $1) }
        return DayAgenda(day: day, phase: phase(on: day), items: items)
    }

    /// What the person should be looking at at `now`: the meal that is on now, else the next one
    /// still ahead today, else the first meal of the next day that has meals.
    public func focus(states: OccurrenceStates = [:], now: Date) -> MealFocus? {
        let today = CalendarDay(now, in: timeZone)
        let open = agenda(on: today, states: states, now: now).items.filter(\.role.isOpenAhead)

        if let first = open.first {
            let following = open.dropFirst().first?.occurrence ?? firstOccurrence(after: today, states: states)
            return MealFocus(kind: first.role == .current ? .now : .next, occurrence: first.occurrence, following: following)
        }

        guard let laterDay = nextDayWithMeals(after: today) else { return nil }
        let meals = occurrences(on: laterDay, states: states)
        let ordered = meals.filter(\.isPending) + meals.filter { !$0.isPending }
        guard let first = ordered.first else { return nil }
        let following = ordered.dropFirst().first ?? firstOccurrence(after: laterDay, states: states)
        return MealFocus(kind: .laterDay, occurrence: first, following: following)
    }

    /// The first meal of the next day that has meals after `day`.
    public func firstOccurrence(after day: CalendarDay, states: OccurrenceStates = [:]) -> MealOccurrence? {
        guard let next = nextDayWithMeals(after: day) else { return nil }
        return occurrences(on: next, states: states).first
    }
}

/// A meal's place in the day at a given moment.
public enum MealRole: String, Hashable, Sendable {
    case done
    case skipped
    /// Its time has come and it is still open.
    case current
    /// The first open meal still ahead today, when nothing is current.
    case next
    /// Ahead, after the next one.
    case upcoming
    /// Its time passed without it being marked.
    case past

    /// Current, next or upcoming: still to be eaten today.
    public var isOpenAhead: Bool {
        self == .current || self == .next || self == .upcoming
    }
}

public struct AgendaItem: Hashable, Identifiable, Sendable {
    public let occurrence: MealOccurrence
    public let role: MealRole

    public init(occurrence: MealOccurrence, role: MealRole) {
        self.occurrence = occurrence
        self.role = role
    }

    public var id: OccurrenceKey { occurrence.key }
}

/// One day's meals and where each one stands.
public struct DayAgenda: Hashable, Sendable {
    public let day: CalendarDay
    public let phase: PlanPhase
    public let items: [AgendaItem]

    public init(day: CalendarDay, phase: PlanPhase, items: [AgendaItem]) {
        self.day = day
        self.phase = phase
        self.items = items
    }

    public var current: AgendaItem? { items.first { $0.role == .current } }
    public var next: AgendaItem? { items.first { $0.role == .next } }

    /// Meals still ahead: current, next and upcoming.
    public var remainingCount: Int { items.filter(\.role.isOpenAhead).count }

    /// The day had meals and every one of them was marked done or skipped.
    public var isComplete: Bool {
        !items.isEmpty && items.allSatisfy { !$0.occurrence.isPending }
    }
}

/// The one meal to put in front of the person.
public struct MealFocus: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Its time has come.
        case now
        /// Later today.
        case next
        /// Nothing left today: the first meal of the next day that has meals.
        case laterDay
    }

    public let kind: Kind
    public let occurrence: MealOccurrence
    /// The meal after this one, today or on the next day with meals.
    public let following: MealOccurrence?

    public init(kind: Kind, occurrence: MealOccurrence, following: MealOccurrence?) {
        self.kind = kind
        self.occurrence = occurrence
        self.following = following
    }
}
