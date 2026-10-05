import SwiftUI

/// Spacing on a 4-point scale. Screens use 20 at the sides; native containers keep their own 16.
public enum AppSpacing {
    public static let xxSmall: CGFloat = 4
    public static let xSmall: CGFloat = 8
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 20
    public static let xLarge: CGFloat = 24
    public static let xxLarge: CGFloat = 32

    /// Leading and trailing margin of a screen's own content.
    public static let screenMargin: CGFloat = 20
    /// The smallest tappable size, whatever the visible size of the control.
    public static let minimumHitTarget: CGFloat = 44
}

/// Corner radii for the few custom surfaces. Lists, sheets and controls keep the system's own.
public enum AppRadius {
    /// Highlighted rows and small grouped content.
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 14
    /// A larger surface, such as a widget preview stage.
    public static let large: CGFloat = 18
}

/// The one brand colour and the few semantic colours built on it. Everything else is a system colour.
public enum AppColors {
    /// Terracotta. Primary actions, the current meal, the selected day. Used sparingly.
    public static var brandAccent: Color { Color("BrandAccent", bundle: .module) }
    /// Text and symbols on a brand-accent fill.
    public static var onBrandAccent: Color { Color("BrandAccentForeground", bundle: .module) }
    /// The quiet wash behind the current or next meal.
    public static var brandWash: Color { Color("BrandAccent", bundle: .module).opacity(0.1) }
    /// Done. Never the only signal: a checkmark always comes with it.
    public static var success: Color { .green }
}

/// Motion. Short, springy, and calm; everything here has a Reduce Motion counterpart.
public enum AppMotion {
    /// State changes: marking a meal, toggles, inserting a row.
    public static var snappy: Animation { .snappy(duration: 0.3, extraBounce: 0) }
    /// Content moving into place: a new day, a new meal in front.
    public static var settle: Animation { .spring(duration: 0.35, bounce: 0.12) }
    /// What replaces movement when Reduce Motion is on: a short cross-fade.
    public static var reduced: Animation { .easeInOut(duration: 0.2) }

    public static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : animation
    }
}

/// Kept for the placeholder screens that still use it.
public enum DesignSystem {
    public enum Spacing {
        public static let small = AppSpacing.xSmall
        public static let medium = AppSpacing.medium
        public static let large = AppSpacing.xLarge
    }
}

extension View {
    /// Runs `body` inside `animation`, or the Reduce Motion cross-fade.
    public func animationAware(_ animation: Animation, reduceMotion: Bool, value: some Equatable) -> some View {
        self.animation(AppMotion.animation(animation, reduceMotion: reduceMotion), value: value)
    }
}

@MainActor
public func withAppAnimation(_ animation: Animation = AppMotion.snappy, reduceMotion: Bool, _ body: () -> Void) {
    withAnimation(AppMotion.animation(animation, reduceMotion: reduceMotion), body)
}
