import Foundation

/// The colour a widget's accents, or its whole background, are drawn in. The raw values are
/// stored, so they never change; what each looks like is decided where it is drawn.
public enum WidgetAccent: String, Codable, CaseIterable, Sendable {
    /// The app's own colour.
    case terracotta
    /// A warm gold: with the Dark background and the Classic typeface, a black-and-gold look.
    case gold
    case orange
    case red
    case pink
    case purple
    case indigo
    case blue
    case teal
    case green
    case graphite
}

/// The tone of a Home Screen widget's background.
public enum WidgetBackgroundStyle: String, Codable, CaseIterable, Sendable {
    /// White in Light Mode, a dark grey in Dark Mode: what widgets look like by default.
    case system
    /// A light wash of the chosen colour.
    case soft
    /// The chosen colour itself, with white text.
    case bold
    /// Dark at any time of day.
    case dark
}

/// The type a Home Screen widget sets a meal's name and time in.
public enum WidgetTypeface: String, Codable, CaseIterable, Sendable {
    /// The system's own type, as the widgets have always been drawn.
    case standard
    /// A serif (New York), for a quieter, more classic widget.
    case serif
}

/// An sRGB colour as plain numbers, so the widget's colours can be checked for contrast in tests
/// that know nothing of SwiftUI.
public struct WidgetRGB: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// 0xRRGGBB.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    public static let white = WidgetRGB(hex: 0xFFFFFF)
    public static let black = WidgetRGB(hex: 0x000000)

    /// This colour drawn at `opacity` over `background`.
    public func over(_ background: WidgetRGB, opacity: Double) -> WidgetRGB {
        WidgetRGB(
            red: red * opacity + background.red * (1 - opacity),
            green: green * opacity + background.green * (1 - opacity),
            blue: blue * opacity + background.blue * (1 - opacity)
        )
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1 to 21. Body text needs 4.5.
    public func contrast(with other: WidgetRGB) -> Double {
        let lighter = max(luminance, other.luminance)
        let darker = min(luminance, other.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// The colours one accent is drawn in. The system's own orange, teal or green are too light for
/// small words on white, so words and marks use a deeper "ink" of the same hue, and the Bold
/// background is a gradient deep enough for white text from top to bottom.
public struct WidgetPalette: Hashable, Sendable {
    /// The colour itself in Light and Dark Mode: swatches, washes, the Soft background.
    public let light: WidgetRGB
    public let dark: WidgetRGB
    /// Words and small marks in the accent on System, Soft and Dark backgrounds.
    public let inkLight: WidgetRGB
    public let inkDark: WidgetRGB
    /// The Bold background, top to bottom.
    public let boldTop: WidgetRGB
    public let boldBottom: WidgetRGB

    /// How strongly the colour is laid over the background for Soft, and again for a chip or the
    /// highlighted meal.
    public static let washOpacity = 0.16
    /// System in Light Mode, and in Dark Mode: not black, the grey iOS draws widgets on.
    public static let lightBackground = WidgetRGB.white
    public static let darkBackground = WidgetRGB(hex: 0x1C1C1E)
    /// The Dark background, the same at any time of day.
    public static let darkStyleBackground = WidgetRGB(hex: 0x121214)
    /// How much white secondary words keep on Bold.
    public static let boldSecondaryOpacity = 0.9
    /// The chip and the highlighted meal on Bold: a shade, not a tint, so white stays readable.
    public static let boldShadeOpacity = 0.2

    public init(light: UInt32, dark: UInt32, inkLight: UInt32, inkDark: UInt32, boldTop: UInt32, boldBottom: UInt32) {
        self.light = WidgetRGB(hex: light)
        self.dark = WidgetRGB(hex: dark)
        self.inkLight = WidgetRGB(hex: inkLight)
        self.inkDark = WidgetRGB(hex: inkDark)
        self.boldTop = WidgetRGB(hex: boldTop)
        self.boldBottom = WidgetRGB(hex: boldBottom)
    }
}

extension WidgetAccent {
    /// Checked in `WidgetPaletteTests`: every word drawn in these reaches 4.5:1 on every background.
    public var palette: WidgetPalette {
        switch self {
        case .terracotta:
            WidgetPalette(light: 0xB94634, dark: 0xE06A55, inkLight: 0x983726, inkDark: 0xF59A86, boldTop: 0xB94634, boldBottom: 0x8E3426)
        case .gold:
            // Gold that is bright enough to read as gold is too light for words on white, so the
            // ink in Light Mode is a deep bronze, and Bold is bronze too.
            WidgetPalette(light: 0xC59B3E, dark: 0xD4AF63, inkLight: 0x7A5A12, inkDark: 0xE0BC72, boldTop: 0x80601A, boldBottom: 0x5A420E)
        case .orange:
            WidgetPalette(light: 0xFF9500, dark: 0xFF9F0A, inkLight: 0x9F3E09, inkDark: 0xFFA94D, boldTop: 0xAE480A, boldBottom: 0x7F3305)
        case .red:
            WidgetPalette(light: 0xFF3B30, dark: 0xFF453A, inkLight: 0xB01D17, inkDark: 0xFF7A70, boldTop: 0xC8221B, boldBottom: 0x931510)
        case .pink:
            WidgetPalette(light: 0xFF2D55, dark: 0xFF375F, inkLight: 0xA81450, inkDark: 0xFF7A9C, boldTop: 0xC2185B, boldBottom: 0x8C0F40)
        case .purple:
            WidgetPalette(light: 0xAF52DE, dark: 0xBF5AF2, inkLight: 0x82339F, inkDark: 0xD59BFF, boldTop: 0x8E3BB8, boldBottom: 0x62257F)
        case .indigo:
            WidgetPalette(light: 0x5856D6, dark: 0x5E5CE6, inkLight: 0x4542B8, inkDark: 0x9D9BFF, boldTop: 0x4B48C8, boldBottom: 0x312EA0)
        case .blue:
            WidgetPalette(light: 0x007AFF, dark: 0x0A84FF, inkLight: 0x0956B5, inkDark: 0x66AFFF, boldTop: 0x0A5DC2, boldBottom: 0x073F87)
        case .teal:
            WidgetPalette(light: 0x30B0C7, dark: 0x40C8E0, inkLight: 0x0A6676, inkDark: 0x5FD4EA, boldTop: 0x0B6F80, boldBottom: 0x064B57)
        case .green:
            WidgetPalette(light: 0x34C759, dark: 0x30D158, inkLight: 0x166A2C, inkDark: 0x4FD97A, boldTop: 0x1B7A35, boldBottom: 0x0F5222)
        case .graphite:
            WidgetPalette(light: 0x3A3A3C, dark: 0xAEAEB2, inkLight: 0x1C1C1E, inkDark: 0xF2F2F7, boldTop: 0x3D3D40, boldBottom: 0x1F1F21)
        }
    }
}

/// What the person chose on the Widgets tab. Applies to every widget.
public struct WidgetPreferences: Codable, Hashable, Sendable {
    /// How long a meal can be kept in front, in minutes: what the Widgets tab offers.
    public static let windowOptions = [30, 45, 60, 90, 120]
    public static let defaultWindowMinutes = 60

    public var showCalories: Bool
    public var showFollowingMeal: Bool
    public var showCompletedMeals: Bool
    public var energyUnit: EnergyUnit
    /// How long a meal stays in front after its time before the next one takes its place.
    public var mealWindowMinutes: Int
    /// Whether the widgets carry an "Eaten" button. On by default, as in `AppSettings`: ticking a
    /// meal off where it is shown is the quickest way to move on, and meals still move on by
    /// themselves for those who never tap it.
    public var showDoneButton: Bool
    public var accent: WidgetAccent
    public var background: WidgetBackgroundStyle
    /// Whether a late start can move the day (`AppSettings.smartMealTimes`): the widget offers
    /// "I'm up" only then.
    public var smartMealTimes: Bool
    /// Lock Screen widgets keep meal names out of sight until the iPhone is unlocked.
    public var hidesMealNamesWhenLocked: Bool
    public var typeface: WidgetTypeface

    public init(
        showCalories: Bool = false,
        showFollowingMeal: Bool = true,
        showCompletedMeals: Bool = true,
        energyUnit: EnergyUnit = .kilocalories,
        mealWindowMinutes: Int = WidgetPreferences.defaultWindowMinutes,
        showDoneButton: Bool = true,
        accent: WidgetAccent = .terracotta,
        background: WidgetBackgroundStyle = .system,
        smartMealTimes: Bool = true,
        hidesMealNamesWhenLocked: Bool = false,
        typeface: WidgetTypeface = .standard
    ) {
        self.showCalories = showCalories
        self.showFollowingMeal = showFollowingMeal
        self.showCompletedMeals = showCompletedMeals
        self.energyUnit = energyUnit
        self.mealWindowMinutes = WidgetPreferences.clampedWindow(mealWindowMinutes)
        self.showDoneButton = showDoneButton
        self.accent = accent
        self.background = background
        self.smartMealTimes = smartMealTimes
        self.hidesMealNamesWhenLocked = hidesMealNamesWhenLocked
        self.typeface = typeface
    }

    /// Between a quarter of an hour and four hours, whatever was stored.
    public static func clampedWindow(_ minutes: Int) -> Int {
        min(max(minutes, 15), 240)
    }

    public var mealWindow: TimeInterval {
        TimeInterval(mealWindowMinutes * 60)
    }

    // Tolerant decoding: a field added later must not make an older file unreadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = WidgetPreferences()
        showCalories = try container.decodeIfPresent(Bool.self, forKey: .showCalories) ?? defaults.showCalories
        showFollowingMeal = try container.decodeIfPresent(Bool.self, forKey: .showFollowingMeal) ?? defaults.showFollowingMeal
        showCompletedMeals = try container.decodeIfPresent(Bool.self, forKey: .showCompletedMeals) ?? defaults.showCompletedMeals
        energyUnit = (try? container.decodeIfPresent(EnergyUnit.self, forKey: .energyUnit)) ?? defaults.energyUnit
        mealWindowMinutes = WidgetPreferences.clampedWindow((try? container.decodeIfPresent(Int.self, forKey: .mealWindowMinutes)) ?? defaults.mealWindowMinutes)
        showDoneButton = (try? container.decodeIfPresent(Bool.self, forKey: .showDoneButton)) ?? defaults.showDoneButton
        // A colour or tone this version does not know — written by a newer one — falls back to the default.
        accent = (try? container.decodeIfPresent(WidgetAccent.self, forKey: .accent)) ?? defaults.accent
        background = (try? container.decodeIfPresent(WidgetBackgroundStyle.self, forKey: .background)) ?? defaults.background
        smartMealTimes = (try? container.decodeIfPresent(Bool.self, forKey: .smartMealTimes)) ?? defaults.smartMealTimes
        hidesMealNamesWhenLocked = (try? container.decodeIfPresent(Bool.self, forKey: .hidesMealNamesWhenLocked)) ?? defaults.hidesMealNamesWhenLocked
        typeface = (try? container.decodeIfPresent(WidgetTypeface.self, forKey: .typeface)) ?? defaults.typeface
    }
}

/// Everything a widget needs, written by the app whenever the plan, a meal's state or a widget
/// preference changes. The widget never opens the database: it reads this one small file and
/// works out each moment of the day from it.
///
/// It carries the plan itself (trimmed to what is drawn) rather than a list of upcoming meals, so
/// the widget keeps moving from meal to meal and day to day for as long as the plan runs, even if
/// the app is not opened for weeks.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    /// Recorded states are kept for this window around the day the snapshot is written.
    public static let stateWindow = -2...14

    public var version: Int
    public var generatedAt: Date
    /// Nil when there is no active plan.
    public var plan: MealPlan?
    /// Occurrence key → state, for the days in `stateWindow`. Missing means pending.
    public var states: [String: OccurrenceState]
    public var preferences: WidgetPreferences
    /// Calendar day ("2026-10-05") → where that day's first meal went after a late start, for the
    /// days in `stateWindow`. Optional so that a snapshot written before late starts existed still
    /// reads; nil and empty both mean every day follows the plan.
    public var dayStarts: [String: DayStart]?

    public init(plan: MealPlan?, states: OccurrenceStates, preferences: WidgetPreferences, generatedAt: Date = .now, timeZone: TimeZone = .current, dayStarts: DayStarts = [:]) {
        let today = CalendarDay(generatedAt, in: timeZone)
        let first = today.adding(days: Self.stateWindow.lowerBound)
        let last = today.adding(days: Self.stateWindow.upperBound)
        self.version = Self.currentVersion
        self.generatedAt = generatedAt
        self.plan = plan?.trimmedForWidget()
        self.states = Dictionary(
            states
                .filter { $0.value != .pending && $0.key.day >= first && $0.key.day <= last }
                .map { ($0.key.description, $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
        self.preferences = preferences
        let starts = dayStarts.filter { $0.key >= first && $0.key <= last }
        self.dayStarts = starts.isEmpty ? nil : Dictionary(uniqueKeysWithValues: starts.map { ($0.key.description, $0.value) })
    }

    /// The late starts this snapshot carries, by day.
    public var recordedDayStarts: DayStarts {
        var result: DayStarts = [:]
        for (text, start) in dayStarts ?? [:] {
            if let day = CalendarDay(text) { result[day] = start }
        }
        return result
    }

    public var occurrenceStates: OccurrenceStates {
        var result: OccurrenceStates = [:]
        for (text, state) in states {
            if let key = OccurrenceKey(text) { result[key] = state }
        }
        return result
    }

    /// A snapshot written by a newer version of the app may mean something this one cannot read.
    public var isReadable: Bool {
        version <= Self.currentVersion
    }

    public static func decode(_ data: Data) throws -> WidgetSnapshot {
        try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

extension WidgetSnapshot {
    /// The sample plan on its first day, with the meals already past marked done: what the
    /// widget gallery and previews show before a real plan exists.
    public static func sample(now: Date = .now, timeZone: TimeZone = .current, preferences: WidgetPreferences = WidgetPreferences()) -> WidgetSnapshot {
        let today = CalendarDay(now, in: timeZone)
        let plan = SamplePlan.keto(startingOn: today)
        let schedule = MealSchedule(plan: plan, timeZone: timeZone, currentWindow: preferences.mealWindow)
        var states: OccurrenceStates = [:]
        for occurrence in schedule.occurrences(on: today) where occurrence.date.addingTimeInterval(schedule.currentWindow) < now {
            states[occurrence.key] = .completed
        }
        return WidgetSnapshot(plan: plan, states: states, preferences: preferences, generatedAt: now, timeZone: timeZone)
    }
}
