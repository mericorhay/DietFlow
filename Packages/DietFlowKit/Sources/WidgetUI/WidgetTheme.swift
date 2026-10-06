import SwiftUI
import UIKit
import WidgetKit
import DesignSystem
import Domain

extension WidgetAccent {
    /// The colour itself, for words and symbols. System colours, so each has a light and a dark
    /// form and keeps its contrast in both.
    public var color: Color {
        switch self {
        case .terracotta: AppColors.brandAccent
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .purple: .purple
        case .indigo: .indigo
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .graphite: .primary
        }
    }

    /// The colour as a surface: a swatch, or the Bold background. Graphite has to be a fixed grey
    /// here, since "primary" is white in a dark setting and would vanish under white text.
    public var fill: Color {
        self == .graphite ? Color(white: 0.24) : color
    }
}

/// How a Home Screen widget is coloured: the person's colour and tone from the Widgets tab,
/// turned into the few colours the widget views ask for. Lock Screen widgets take none of it;
/// iOS draws those in its own colours.
public struct WidgetTheme: Hashable, Sendable {
    public let accent: WidgetAccent
    public let background: WidgetBackgroundStyle

    public init(accent: WidgetAccent, background: WidgetBackgroundStyle) {
        self.accent = accent
        self.background = background
    }

    public init(_ preferences: WidgetPreferences) {
        self.init(accent: preferences.accent, background: preferences.background)
    }

    /// The app's own look, and what Lock Screen widgets always use.
    public static let standard = WidgetTheme(accent: .terracotta, background: .system)

    /// The line above a meal, the Done button, the status marks: on a Bold background these are
    /// white, because the colour is already the background.
    public var tint: Color {
        background == .bold ? .white : accent.color
    }

    /// The soft patch behind the meal in front.
    public var wash: Color {
        background == .bold ? Color.white.opacity(0.2) : accent.color.opacity(0.14)
    }

    /// The "day complete" checkmark.
    public var success: Color {
        background == .bold ? .white : AppColors.success
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

/// Hands the theme to everything inside a Home Screen widget. On a Bold background the text is
/// white and a little softer white, since the system's greys are tuned for neutral backgrounds.
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
            content.environment(\.widgetTheme, .standard)
        } else if theme.background == .bold {
            content
                .environment(\.widgetTheme, theme)
                .environment(\.colorScheme, .dark)
                .foregroundStyle(Color.white, Color.white.opacity(0.8))
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

    public var body: some View {
        switch theme.background {
        case .system:
            Color(.systemBackground)
        case .soft:
            ZStack {
                Color(.systemBackground)
                theme.accent.color.opacity(0.16)
            }
        case .bold:
            ZStack {
                theme.accent.fill
                // Deepens the colour towards the bottom, and enough overall for white text to
                // read on the lighter ones: orange, teal, green.
                LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
            }
        case .dark:
            Color(red: 0.07, green: 0.07, blue: 0.08)
        }
    }
}
