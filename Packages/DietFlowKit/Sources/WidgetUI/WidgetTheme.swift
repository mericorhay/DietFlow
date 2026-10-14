import SwiftUI
import UIKit
import WidgetKit
import DesignSystem
import Domain

extension Color {
    /// One fixed sRGB colour.
    init(_ rgb: WidgetRGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// One colour in Light Mode and another in Dark Mode, resolved wherever it is drawn — including
    /// inside a widget forced into Dark Mode by its Bold or Dark background.
    init(light: WidgetRGB, dark: WidgetRGB) {
        self.init(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        })
    }
}

extension WidgetAccent {
    /// The colour itself, for swatches, washes and the Soft background. Each has a light and a
    /// dark form (`WidgetPalette`).
    public var color: Color {
        Color(light: palette.light, dark: palette.dark)
    }

    /// The colour as a surface: a swatch, or the Bold background. Graphite is a fixed grey here, so
    /// white on it reads in any setting.
    public var fill: Color {
        self == .graphite ? Color(palette.boldTop) : color
    }

    /// Words and small marks in the accent on System, Soft and Dark backgrounds: a deeper form of
    /// the colour that reaches 4.5:1 there (`WidgetPaletteTests`), where the system's own orange or
    /// green on white would not.
    public var ink: Color {
        Color(light: palette.inkLight, dark: palette.inkDark)
    }
}

/// How a Home Screen widget is coloured: the person's colour and tone from the Widgets tab,
/// turned into the few colours the widget views ask for. Lock Screen widgets take none of it;
/// iOS draws those in its own colours.
public struct WidgetTheme: Hashable, Sendable {
    public let accent: WidgetAccent
    public let background: WidgetBackgroundStyle
    public let typeface: WidgetTypeface

    public init(accent: WidgetAccent, background: WidgetBackgroundStyle, typeface: WidgetTypeface = .standard) {
        self.accent = accent
        self.background = background
        self.typeface = typeface
    }

    public init(_ preferences: WidgetPreferences) {
        self.init(accent: preferences.accent, background: preferences.background, typeface: preferences.typeface)
    }

    /// The app's own look, and what Lock Screen widgets always use.
    public static let standard = WidgetTheme(accent: .terracotta, background: .system)

    /// Words and marks in the accent: the lead chip, the time, the status marks, the buttons. On a
    /// Bold background these are white, because the colour is already the background.
    public var ink: Color {
        background == .bold ? .white : accent.ink
    }

    /// The accent for marks that are not words: rings, bars, the check. The same as `ink`, so a
    /// ring reads as clearly as the words beside it.
    public var tint: Color { ink }

    /// The patch behind the chip, the meal tile and the meal in front: a wash of the colour, or on
    /// Bold a shade, which keeps white text readable where a white wash would not.
    public var wash: Color {
        background == .bold ? Color.black.opacity(WidgetPalette.boldShadeOpacity) : accent.color.opacity(WidgetPalette.washOpacity)
    }

    /// The "day complete" checkmark.
    public var success: Color {
        background == .bold ? .white : AppColors.success
    }

    /// A meal's name or time in the person's typeface. `design` is what the standard type uses at
    /// that place, so the standard look is unchanged; the serif is set a step lighter, since a bold
    /// serif reads heavy at widget sizes.
    public func display(_ style: Font.TextStyle, weight: Font.Weight = .bold, design: Font.Design = .default) -> Font {
        switch typeface {
        case .standard:
            .system(style, design: design, weight: weight)
        case .serif:
            .system(style, design: .serif, weight: weight == .bold ? .semibold : weight)
        }
    }

    /// The standard colours with the person's typeface: what a widget is drawn in where iOS
    /// chooses the colours, on the Lock Screen and with tinted or clear icons.
    func withStandardColors() -> WidgetTheme {
        WidgetTheme(accent: Self.standard.accent, background: Self.standard.background, typeface: typeface)
    }

    /// Bold and Dark are dark surfaces whatever the phone is set to, so everything on them is
    /// drawn as it would be in Dark Mode.
    var colorScheme: ColorScheme? {
        switch background {
        case .bold, .dark: .dark
        case .system, .soft: nil
        }
    }
}

private struct WidgetThemeKey: EnvironmentKey {
    static let defaultValue = WidgetTheme.standard
}

extension EnvironmentValues {
    public var widgetTheme: WidgetTheme {
        get { self[WidgetThemeKey.self] }
        set { self[WidgetThemeKey.self] = newValue }
    }
}

/// Where a widget view is being drawn, which decides what in it may move or be tapped.
public enum WidgetRendering: Hashable, Sendable {
    /// A picture of the widget at one moment of an example day (onboarding): countdowns are worked
    /// out once, from the entry's own time, and nothing opens anything.
    case preview
    /// The widget at the real time, inside the app (the Widgets tab): countdowns run, but taps are
    /// left to the screen around it.
    case livePreview
    /// The real widget, in the widget extension: countdowns run and rows open their meal.
    case widget

    var usesLiveTime: Bool { self != .preview }
    var opensLinks: Bool { self == .widget }
}

private struct WidgetRenderingKey: EnvironmentKey {
    static let defaultValue = WidgetRendering.preview
}

extension EnvironmentValues {
    /// Set to `.widget` by the widget extension and `.livePreview` by the Widgets tab.
    public var widgetRendering: WidgetRendering {
        get { self[WidgetRenderingKey.self] }
        set { self[WidgetRenderingKey.self] = newValue }
    }
}

/// Hands the theme to everything inside a Home Screen widget. On a Bold background the text is
/// white, and secondary text a slightly softer white, since the system's greys are tuned for
/// neutral backgrounds.
struct WidgetThemed: ViewModifier {
    let theme: WidgetTheme
    let family: WidgetFamily
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var isHomeScreen: Bool {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: true
        default: false
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        // With tinted or clear icons iOS takes the background away and draws the widget in its own
        // colours; white text chosen for a Bold background would be left on nothing.
        if !isHomeScreen || renderingMode != .fullColor {
            content.environment(\.widgetTheme, theme.withStandardColors())
        } else if theme.background == .bold {
            content
                .environment(\.widgetTheme, theme)
                .environment(\.colorScheme, .dark)
                .foregroundStyle(Color.white, Color.white.opacity(WidgetPalette.boldSecondaryOpacity))
        } else if let scheme = theme.colorScheme {
            content
                .environment(\.widgetTheme, theme)
                .environment(\.colorScheme, scheme)
        } else {
            content.environment(\.widgetTheme, theme)
        }
    }
}

/// What a Home Screen widget is drawn on. The widget extension uses it as the container
/// background, and the app's previews draw the same thing, so what is chosen is what appears.
public struct WidgetThemeBackground: View {
    private let theme: WidgetTheme

    public init(_ preferences: WidgetPreferences) {
        theme = WidgetTheme(preferences)
    }

    /// White in Light Mode and, in Dark Mode, the grey iOS draws its own widgets on: pure black
    /// makes a widget look like a hole in the Home Screen.
    private var automatic: Color {
        Color(light: WidgetPalette.lightBackground, dark: WidgetPalette.darkBackground)
    }

    public var body: some View {
        switch theme.background {
        case .system:
            automatic
        case .soft:
            ZStack {
                automatic
                theme.accent.color.opacity(WidgetPalette.washOpacity)
            }
        case .bold:
            // Deep enough at the top for white words, deeper still towards the bottom.
            LinearGradient(
                colors: [Color(theme.accent.palette.boldTop), Color(theme.accent.palette.boldBottom)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .dark:
            Color(WidgetPalette.darkStyleBackground)
        }
    }
}
