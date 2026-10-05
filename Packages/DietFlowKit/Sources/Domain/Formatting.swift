import Foundation

/// How energy is shown. Plans store kilocalories; kilojoules are a display choice.
public enum EnergyUnit: String, Codable, CaseIterable, Sendable {
    case kilocalories
    case kilojoules

    /// "510 kcal" or "2,134 kJ", in the person's locale.
    public func format(kilocalories: Int, locale: Locale = .current) -> String {
        let energy = Measurement(value: Double(kilocalories), unit: UnitEnergy.kilocalories)
        let shown = self == .kilocalories ? energy : energy.converted(to: .kilojoules)
        return shown.formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }

    public var displayName: String {
        switch self {
        case .kilocalories: String(localized: "energyUnit.kilocalories", bundle: .module)
        case .kilojoules: String(localized: "energyUnit.kilojoules", bundle: .module)
        }
    }
}

public enum NutritionFormat {
    /// "42 g", with at most one decimal.
    public static func grams(_ value: Double, locale: Locale = .current) -> String {
        Measurement(value: value, unit: UnitMass.grams).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))
                .locale(locale)
        )
    }
}

public enum RelativeTimeText {
    /// "in 42 min", "in 2 hr, 10 min": how long until `date`, rounded up to the minute. Nil when
    /// `date` has passed or is a day or more away, where a relative time stops being useful.
    public static func until(_ date: Date, from now: Date, locale: Locale = .current) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0, seconds < 24 * 3600 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        return until(minutes: minutes, locale: locale)
    }

    public static func until(minutes: Int, locale: Locale = .current) -> String {
        let duration = Duration.seconds(max(minutes, 1) * 60)
        let amount = duration.formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2).locale(locale)
        )
        return String(localized: "relative.inDuration", defaultValue: "in \(amount)", bundle: .module, locale: locale)
    }

    /// "20 min ago": how long since `date` started, for a meal that is on now.
    public static func since(_ date: Date, from now: Date, locale: Locale = .current) -> String? {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 60, seconds < 24 * 3600 else { return nil }
        let duration = Duration.seconds(Int(seconds / 60) * 60)
        let amount = duration.formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2).locale(locale)
        )
        return String(localized: "relative.agoDuration", defaultValue: "\(amount) ago", bundle: .module, locale: locale)
    }
}

extension MealRole {
    /// How VoiceOver describes the role after a meal's name. Nil for meals simply ahead.
    public var accessibilityDescription: String? {
        switch self {
        case .current: String(localized: "mealRole.current", bundle: .module)
        case .next: String(localized: "mealRole.next", bundle: .module)
        case .done: String(localized: "mealRole.done", bundle: .module)
        case .skipped: String(localized: "mealRole.skipped", bundle: .module)
        case .past: String(localized: "mealRole.past", bundle: .module)
        case .upcoming: nil
        }
    }
}

public enum MealAccessibility {
    /// "Lunch, 2:00 PM, Grilled Chicken Caesar Salad, next meal."
    public static func label(typeLabel: String, date: Date, title: String, role: MealRole?, locale: Locale = .current) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        if let state = role?.accessibilityDescription {
            return String(localized: "accessibility.mealWithState", defaultValue: "\(typeLabel), \(time), \(title), \(state)", bundle: .module, locale: locale)
        }
        return String(localized: "accessibility.meal", defaultValue: "\(typeLabel), \(time), \(title)", bundle: .module, locale: locale)
    }
}
