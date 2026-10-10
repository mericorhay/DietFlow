import Foundation

/// When one day really started for the person: the time their first meal moved to because they got
/// up later than the plan assumes. People do not wake at the same time every day; a plan written
/// for 08:00 should not leave someone who slept in until ten two meals behind before they have
/// opened their eyes.
///
/// Like what happened to each meal, it is kept apart from the plan, keyed by calendar day, so a
/// late Saturday never edits a plan that repeats.
public struct DayStart: Codable, Hashable, Sendable {
    /// How the app learned the day started late.
    public enum Source: String, Codable, Hashable, Sendable {
        /// The person said so on Today ("I'm up").
        case morning
        /// From the first meal's reminder ("Just Woke Up").
        case reminder
        /// From a Shortcut, typically an automation that runs when the alarm is stopped.
        case shortcut
        /// The first meal was marked eaten well after its time; the rest of the day followed it.
        case firstMeal
        /// From the widget's "I'm up" button.
        case widget
    }

    /// Where the day's first meal goes. Every other meal of the day is laid out after it.
    public var firstMeal: TimeOfDay
    /// When the person got up, when they said; shown back to them ("Up at 09:40").
    public var wake: TimeOfDay?
    public var source: Source

    public init(firstMeal: TimeOfDay, wake: TimeOfDay? = nil, source: Source) {
        self.firstMeal = firstMeal
        self.wake = wake
        self.source = source
    }

    /// The day started at `wake`: the first meal half an hour later, the way most people eat
    /// breakfast, rounded to five minutes.
    public static func wokeUp(at wake: TimeOfDay, source: Source) -> DayStart {
        DayStart(firstMeal: DayShift.rounded(TimeOfDay(minutesSinceMidnight: min(wake.minutesSinceMidnight + DayShift.breakfastLead, DayShift.latestMeal))), wake: wake, source: source)
    }
}

/// Recorded day starts by calendar day. A missing day follows the plan as written.
public typealias DayStarts = [CalendarDay: DayStart]

/// Lays a day's meals out again after a late start. Pure arithmetic on clock times, so it is the
/// same in the app, the widget and the reminders, and tested.
///
/// The first meal moves to where the day now starts. The last meal stays where it is while the day
/// still has room — dinner at seven is worth keeping — and moves later only as much as the day needs
/// to stay at least `comfortableShare` of its usual length, at most an hour and a half, and never
/// past half past eleven: a late morning should not mean dinner at midnight. Everything in between
/// keeps its place in proportion, at least three quarters of an hour apart where the day allows it.
/// Meals only ever move later, never earlier, and never change order, so "what comes next" means
/// the same thing it did. A day that starts after its last meal's time is left as it is: cramming a
/// whole day's eating into the night helps nobody.
public enum DayShift {
    /// Minutes from getting up to the first meal.
    public static let breakfastLead = 30
    /// The most the day's last meal is pushed back, in minutes.
    public static let lastMealDelay = 90
    /// The shortest a shifted day may be, as a share of the plan's own first-to-last span, before
    /// the last meal is moved back to make room.
    public static let comfortableShare = 0.6
    /// The least time between two meals, in minutes, where the day has room for it.
    public static let minimumGap = 45
    /// No meal is moved past this, in minutes after midnight (23:30): a meal pushed past midnight
    /// would belong to the next day.
    public static let latestMeal = 23 * 60 + 30
    /// A start this little after the plan's first meal changes nothing: nobody needs breakfast
    /// moved by ten minutes.
    public static let threshold = 15

    /// The clock times `times` (one day's meals, in order) move to when the day starts with its first
    /// meal at `firstMeal`. Returns `times` unchanged when the day started on time or early.
    public static func times(_ times: [TimeOfDay], firstMeal: TimeOfDay) -> [TimeOfDay] {
        guard let first = times.first, let last = times.last else { return times }
        let template = times.map(\.minutesSinceMidnight)
        let start = min(firstMeal.minutesSinceMidnight, latestMeal)
        let delay = start - first.minutesSinceMidnight
        guard delay >= threshold else { return times }

        let t0 = template[0]
        let tn = last.minutesSinceMidnight
        if times.count > 1, start >= tn { return times }
        // The last meal moves only as far as the day needs room, by less than the first, within the
        // latest time, and never before where the day now starts.
        let needed = max(0, Int((comfortableShare * Double(tn - t0)).rounded(.up)) - (tn - start))
        var end = tn + min(delay, lastMealDelay, needed)
        end = max(min(end, max(latestMeal, tn)), start)

        var shifted: [Double] = template.map { t in
            guard tn > t0 else { return Double(start) }
            let share = Double(t - t0) / Double(tn - t0)
            return Double(start) + share * Double(end - start)
        }
        // Room between meals where there is any: push forward, then pull back from the latest time.
        for index in shifted.indices.dropFirst() {
            shifted[index] = max(shifted[index], shifted[index - 1] + Double(minimumGap))
        }
        let ceiling = Double(max(latestMeal, tn))
        if let lastIndex = shifted.indices.last, shifted[lastIndex] > ceiling {
            shifted[lastIndex] = ceiling
            for index in shifted.indices.dropLast().reversed() {
                shifted[index] = min(shifted[index], shifted[index + 1] - Double(minimumGap))
            }
        }
        // Whatever happened above: never before the start, never before the plan's own time, and in
        // order.
        var result: [Int] = []
        for (index, value) in shifted.enumerated() {
            var minutes = Int(value.rounded())
            minutes = max(minutes, template[index], start)
            minutes = min(minutes, max(Int(ceiling), template[index]))
            if let previous = result.last { minutes = max(minutes, previous) }
            result.append(minutes)
        }
        return result.enumerated().map { index, minutes in
            // Round to five minutes for display, keeping the first meal exactly where it was put and
            // the order intact.
            let value = index == 0 ? minutes : roundedMinutes(minutes)
            return TimeOfDay(minutesSinceMidnight: min(value, 23 * 60 + 59))
        }.reduce(into: [TimeOfDay]()) { kept, time in
            kept.append(kept.last.map { max($0, time) } ?? time)
        }
    }

    /// How far a start moves the day, in minutes: the first meal's delay, or 0 when it changes
    /// nothing.
    public static func delay(_ times: [TimeOfDay], firstMeal: TimeOfDay) -> Int {
        guard let first = times.first, let shiftedFirst = Self.times(times, firstMeal: firstMeal).first else { return 0 }
        return shiftedFirst.minutesSinceMidnight - first.minutesSinceMidnight
    }

    static func roundedMinutes(_ minutes: Int) -> Int {
        Int((Double(minutes) / 5).rounded()) * 5
    }

    static func rounded(_ time: TimeOfDay) -> TimeOfDay {
        TimeOfDay(minutesSinceMidnight: min(roundedMinutes(time.minutesSinceMidnight), 23 * 60 + 55))
    }
}
