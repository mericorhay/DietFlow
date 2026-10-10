import Foundation

/// A place in the app a link can open: what the widget opens when tapped, and what a Shortcut or
/// a notification can point at. `dietflow://meal/<occurrence>` opens that meal on that day.
public enum AppLink: Hashable, Sendable {
    case today
    case meal(OccurrenceKey)
    /// Cook mode for that meal on that day: the widget's "How to make it".
    case cook(OccurrenceKey)
    case plan
    case widgets
    case importPlan

    /// Registered in Config/DietFlow-Info.plist.
    public static let scheme = "dietflow"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .today:
            components.host = "today"
        case .meal(let key):
            components.host = "meal"
            components.path = "/\(key.description)"
        case .cook(let key):
            components.host = "cook"
            components.path = "/\(key.description)"
        case .plan:
            components.host = "plan"
        case .widgets:
            components.host = "widgets"
        case .importPlan:
            components.host = "import"
        }
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        switch host {
        case "today":
            self = .today
        case "meal", "cook":
            let text = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let key = OccurrenceKey(text) else { return nil }
            self = host == "cook" ? .cook(key) : .meal(key)
        case "plan":
            self = .plan
        case "widgets":
            self = .widgets
        case "import":
            self = .importPlan
        default:
            return nil
        }
    }
}
