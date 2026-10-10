import Foundation
import SwiftUI
import UIKit
import AppCore
import DesignSystem
import Domain

// The smart day on Today. People do not wake at the same time every day; a plan written for 08:00
// should not leave someone who slept until ten two meals behind. In the morning Today asks once,
// lightly, and a late start moves the day's meals with one tap (`DayShift`, the same arithmetic the
// widget and the reminders use). Instant, on the phone, no assistant.

// MARK: The question

/// What Today asks in the morning, if anything. Asked only while smart meal times are on, nothing
/// of the day is marked yet, and the day has not been started some other way (the reminder, a
/// Shortcut, the widget, or marking the first meal late).
enum MorningQuestion {
    /// From 04:00 until shortly after the first meal: up already? Saying so changes nothing when
    /// the person is on time.
    case upAlready(first: Meal)
    /// Well after the first meal, with nothing marked: the day probably started late. `planned`
    /// and `shifted` are the day's clock times, meal by meal, as written and as they would move to
    /// for someone up now.
    case lateStart(first: Meal, meals: [Meal], planned: [TimeOfDay], shifted: [TimeOfDay])

    /// The earliest the morning question is asked: earlier than this is still the night.
    static let morningBegins = 4 * 60
    /// How long after the first meal's time the question stays "up already?".
    static let grace = 20

    static func at(_ now: Date, today: CalendarDay, store: MealPlanStore) -> MorningQuestion? {
        guard store.settings.smartMealTimes, store.dayStart(on: today) == nil, let schedule = store.schedule else { return nil }
        let meals = schedule.meals(on: today)
        guard let first = meals.first else { return nil }
        guard schedule.occurrences(on: today, states: store.states).allSatisfy(\.isPending) else { return nil }
        let clock = TimeOfDay(now)
        guard clock.minutesSinceMidnight >= morningBegins else { return nil }
        if clock.minutesSinceMidnight < first.time.minutesSinceMidnight + grace {
            return .upAlready(first: first)
        }
        let planned = meals.map(\.time)
        let shifted = DayShift.times(planned, firstMeal: DayStart.wokeUp(at: clock, source: .morning).firstMeal)
        // Too late in the day to move anything: cramming a day's eating into the night helps nobody.
        guard shifted != planned else { return nil }
        return .lateStart(first: first, meals: meals, planned: planned, shifted: shifted)
    }
}

// MARK: Morning card

/// Above the hero in the morning. Before the first meal, a light "up already?" row; well after it,
/// a card that shows exactly how the day would move, before anything changes.
struct MorningCard: View {
    let question: MorningQuestion
    let today: CalendarDay
    /// The hero already shows a prominent Done; then this card's main button stays bordered, so
    /// only one action leads.
    let isQuiet: Bool
    let onUp: () -> Void
    let onKeepTimes: () -> Void
    let onPickWakeTime: () -> Void

    var body: some View {
        switch question {
        case .upAlready(let first):
            upAlready(first)
        case .lateStart(let first, let meals, let planned, let shifted):
            lateStart(first: first, meals: meals, planned: planned, shifted: shifted)
        }
    }

    private func upAlready(_ first: Meal) -> some View {
        let firstTime = first.time.date(on: today).formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("today.morning.up.title", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                    Text(String(localized: "today.morning.up.message", defaultValue: "\(first.typeLabel) is at \(firstTime). Up later than that? Your meals move with you.", bundle: .module))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "sun.horizon.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.title3)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.small) { upButtons }
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) { upButtons }
            }
        }
        .padding(.vertical, AppSpacing.xSmall)
    }

    @ViewBuilder
    private var upButtons: some View {
        Button(action: onUp) {
            Label {
                Text("today.morning.up.action", bundle: .module)
            } icon: {
                Image(systemName: "sun.max")
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(AppColors.brandAccent)
        Button(action: onPickWakeTime) {
            Text("today.morning.up.earlier", bundle: .module)
        }
        .buttonStyle(.borderless)
        .tint(AppColors.brandAccent)
    }

    private func lateStart(first: Meal, meals: [Meal], planned: [TimeOfDay], shifted: [TimeOfDay]) -> some View {
        let firstTime = first.time.date(on: today).formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: AppSpacing.small) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "today.morning.late.title", defaultValue: "Late start? \(first.typeLabel) was \(firstTime)", bundle: .module))
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("today.morning.late.message", bundle: .module)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "sun.horizon.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.title3)
            }

            ShiftPreview(day: today, meals: meals, planned: planned, shifted: shifted, rollsIn: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.small) { lateButtons }
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) { lateButtons }
            }
            Button(action: onPickWakeTime) {
                Text("today.morning.late.wokeAt", bundle: .module)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .tint(AppColors.brandAccent)
        }
        .padding(AppSpacing.medium)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    @ViewBuilder
    private var lateButtons: some View {
        if isQuiet {
            shiftButton.buttonStyle(.bordered)
        } else {
            shiftButton.buttonStyle(.borderedProminent)
        }
        Button(action: onKeepTimes) {
            Text("today.morning.late.keep", bundle: .module)
        }
        .buttonStyle(.bordered)
        .tint(Color.secondary)
    }

    private var shiftButton: some View {
        Button(action: onUp) {
            Label {
                Text("today.morning.late.shift", bundle: .module)
            } icon: {
                Image(systemName: "clock.arrow.circlepath")
            }
        }
        .tint(AppColors.brandAccent)
    }
}

// MARK: Preview of a moved day

/// The day's meals with the plan's time struck through and the time they move to beside it, so
/// the change is seen before it is made. With `rollsIn` the new times count up from the old ones
/// when they appear.
struct ShiftPreview: View {
    let day: CalendarDay
    let meals: [Meal]
    let planned: [TimeOfDay]
    let shifted: [TimeOfDay]
    var rollsIn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxSmall) {
            ForEach(meals.indices, id: \.self) { index in
                row(
                    meals[index],
                    planned: index < planned.count ? planned[index] : meals[index].time,
                    shifted: index < shifted.count ? shifted[index] : meals[index].time
                )
            }
        }
        .onAppear {
            guard rollsIn, !isRevealed else { return }
            if reduceMotion {
                isRevealed = true
            } else {
                withAnimation(AppMotion.settle.delay(0.25)) { isRevealed = true }
            }
        }
    }

    private func row(_ meal: Meal, planned: TimeOfDay, shifted: TimeOfDay) -> some View {
        let old = planned.date(on: day)
        let new = shifted.date(on: day)
        let moves = planned != shifted
        let shown = rollsIn && !isRevealed ? old : new
        return HStack(spacing: AppSpacing.xSmall) {
            MealGlyph(meal.type, size: 24)
            Text(meal.typeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: AppSpacing.xSmall)
            if moves {
                Text(old, format: .dateTime.hour().minute())
                    .font(.subheadline)
                    .monospacedDigit()
                    .strikethrough()
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(shown, format: .dateTime.hour().minute())
                .font(.subheadline.weight(moves ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(moves ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .contentTransition(.numericText())
                .animationAware(AppMotion.snappy, reduceMotion: reduceMotion, value: shown)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(meal, old: old, new: new, moves: moves))
    }

    private func accessibilityText(_ meal: Meal, old: Date, new: Date, moves: Bool) -> String {
        let from = old.formatted(date: .omitted, time: .shortened)
        guard moves else {
            return String(localized: "today.shift.preview.stays", defaultValue: "\(meal.typeLabel), stays at \(from)", bundle: .module)
        }
        let to = new.formatted(date: .omitted, time: .shortened)
        return String(localized: "today.shift.preview.moves", defaultValue: "\(meal.typeLabel), moves from \(from) to \(to)", bundle: .module)
    }
}

// MARK: Wake time

/// "I woke up at…": a time on today, and the day's meals following it live as the wheel turns.
struct WakeTimeSheet: View {
    let today: CalendarDay
    let now: Date
    let meals: [Meal]
    let onSave: (TimeOfDay) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var wake: Date

    init(today: CalendarDay, now: Date, meals: [Meal], onSave: @escaping (TimeOfDay) -> Void) {
        self.today = today
        self.now = now
        self.meals = meals
        self.onSave = onSave
        // Half an hour ago is a likelier answer than this very minute.
        let start = today.startDate()
        self._wake = State(initialValue: max(start, now.addingTimeInterval(-30 * 60)))
    }

    private var planned: [TimeOfDay] { meals.map(\.time) }

    private var shifted: [TimeOfDay] {
        DayShift.times(planned, firstMeal: DayStart.wokeUp(at: TimeOfDay(wake), source: .morning).firstMeal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(selection: $wake, in: today.startDate()...max(today.startDate(), now), displayedComponents: .hourAndMinute) {
                        Text("today.wake.picker", bundle: .module)
                    }
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("today.wake.footer", bundle: .module)
                }
                if !meals.isEmpty {
                    Section {
                        ShiftPreview(day: today, meals: meals, planned: planned, shifted: shifted)
                            .padding(.vertical, AppSpacing.xxSmall)
                    } header: {
                        Text("today.wake.preview", bundle: .module)
                    }
                }
            }
            .navigationTitle(Text("today.wake.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("today.wake.cancel", bundle: .module)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(TimeOfDay(wake))
                        dismiss()
                    } label: {
                        Text("today.wake.save", bundle: .module)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.selection, trigger: TimeOfDay(wake))
    }
}

// MARK: Shifted day

/// Under the meals heading while today runs later than the plan: by how much, why, and a way back.
struct DayShiftBanner: View {
    let delay: Int
    let start: DayStart?
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(AppColors.brandAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "today.shift.banner", defaultValue: "Day moved \(TodayFormat.duration(minutes: delay)) later", bundle: .module))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onUndo) {
                Text("today.shift.undo", bundle: .module)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: AppSpacing.minimumHitTarget)
            }
            .buttonStyle(.borderless)
            .tint(AppColors.brandAccent)
            .accessibilityHint(Text("today.shift.undoHint", bundle: .module))
        }
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.xxSmall)
        .background(AppColors.brandWash, in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
    }

    /// Why the day moved, in the person's terms.
    private var reason: String? {
        guard let start else { return nil }
        if let wake = start.wake {
            let time = wake.date(on: CalendarDay.today()).formatted(date: .omitted, time: .shortened)
            return String(localized: "today.shift.reason.wake", defaultValue: "You were up at \(time).", bundle: .module)
        }
        if start.source == .firstMeal {
            return String(localized: "today.shift.reason.firstMeal", bundle: .module)
        }
        return nil
    }
}

/// Small formatting shared by Today's views.
enum TodayFormat {
    /// "1 hr, 30 min", "45 min".
    static func duration(minutes: Int) -> String {
        Duration.seconds(max(minutes, 1) * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2)
        )
    }
}
