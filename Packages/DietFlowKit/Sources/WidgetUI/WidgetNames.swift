import Foundation
import Domain

// What the widgets, their colours and their tones are called, wherever the app names them: the
// Widgets tab and the first-launch introduction both let the person choose between them.

extension MealWidgetKind {
    public var name: String {
        switch self {
        case .nextMeal: String(localized: "widget.kind.nextMeal", bundle: .module)
        case .today: String(localized: "widget.kind.today", bundle: .module)
        case .progress: String(localized: "widget.kind.progress", bundle: .module)
        }
    }
}

extension WidgetAccent {
    public var name: String {
        switch self {
        case .terracotta: String(localized: "widget.color.terracotta", bundle: .module)
        case .orange: String(localized: "widget.color.orange", bundle: .module)
        case .red: String(localized: "widget.color.red", bundle: .module)
        case .pink: String(localized: "widget.color.pink", bundle: .module)
        case .purple: String(localized: "widget.color.purple", bundle: .module)
        case .indigo: String(localized: "widget.color.indigo", bundle: .module)
        case .blue: String(localized: "widget.color.blue", bundle: .module)
        case .teal: String(localized: "widget.color.teal", bundle: .module)
        case .green: String(localized: "widget.color.green", bundle: .module)
        case .graphite: String(localized: "widget.color.graphite", bundle: .module)
        }
    }
}

extension WidgetBackgroundStyle {
    public var name: String {
        switch self {
        case .system: String(localized: "widget.background.system", bundle: .module)
        case .soft: String(localized: "widget.background.soft", bundle: .module)
        case .bold: String(localized: "widget.background.bold", bundle: .module)
        case .dark: String(localized: "widget.background.dark", bundle: .module)
        }
    }
}
