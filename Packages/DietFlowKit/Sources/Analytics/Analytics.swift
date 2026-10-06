import Foundation
@preconcurrency import PostHog
import Synchronization

/// Product analytics, through PostHog. The one place the app talks to it.
///
/// What leaves the phone is which features are used, where a limit is hit and whether DietFlow
/// Plus is bought: named events with a handful of plain properties. Never a meal, a plan's name, a
/// note, a pasted list or a photo. There is no session replay and no automatic screen or tap
/// capture. The id is a random one PostHog makes on the phone, never tied to an Apple Account.
///
/// Sharing is on unless the person turns it off in Settings; turned off, nothing is sent and
/// nothing is queued. The key comes from `Analytics.json` in the app bundle, which CI writes from
/// repository secrets. Without it nothing is ever sent, and every call here does nothing.
public enum Analytics {
    private struct Config: Decodable {
        var apiKey: String
        var host: String?
    }

    /// Stored as the opt-out, so a phone that has never seen the switch shares.
    private static let optOutKey = "analytics.optOut"
    private static let started = Mutex(false)

    /// Starts PostHog once, when the build has a key and the person has not turned sharing off.
    public static func start(bundle: Bundle = .main) {
        guard isOn else { return }
        guard let url = bundle.url(forResource: "Analytics", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Config.self, from: data),
              !config.apiKey.isEmpty
        else { return }
        let first = started.withLock { value in
            defer { value = true }
            return !value
        }
        guard first else { return }

        let settings = PostHogConfig(apiKey: config.apiKey, host: config.host ?? "https://us.i.posthog.com")
        // App opened, backgrounded, installed, updated: what retention is read from.
        settings.captureApplicationLifecycleEvents = true
        settings.captureScreenViews = false
        PostHogSDK.shared.setup(settings)
    }

    /// Whether this build can share anything at all. Without a key the Settings switch is left
    /// out, rather than offer a choice that changes nothing.
    public static var isConfigured: Bool {
        Bundle.main.url(forResource: "Analytics", withExtension: "json") != nil
    }

    /// The Settings switch. On until the person turns it off.
    public static var isOn: Bool {
        get { !UserDefaults.standard.bool(forKey: optOutKey) }
        set {
            UserDefaults.standard.set(!newValue, forKey: optOutKey)
            if newValue {
                start()
                if started.withLock({ $0 }) { PostHogSDK.shared.optIn() }
            } else if started.withLock({ $0 }) {
                PostHogSDK.shared.optOut()
            }
        }
    }

    /// One thing that happened, with its plain properties.
    public static func track(_ event: String, _ properties: [String: AnalyticsValue] = [:]) {
        guard isOn, started.withLock({ $0 }) else { return }
        PostHogSDK.shared.capture(event, properties: properties.mapValues(\.raw))
    }

    /// Sent with every event from now on: the tier, the app's language.
    public static func remember(_ properties: [String: AnalyticsValue]) {
        guard isOn, started.withLock({ $0 }) else { return }
        PostHogSDK.shared.register(properties.mapValues(\.raw))
    }

    /// Sends what is waiting now, rather than at the next batch: called when the app leaves the
    /// screen, so a short session is not lost.
    public static func flush() {
        guard isOn, started.withLock({ $0 }) else { return }
        PostHogSDK.shared.flush()
    }
}

/// The only kinds of value an event may carry: no free text from the person gets in by accident.
public enum AnalyticsValue: Sendable, Hashable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    case text(String)
    case number(Double)
    case flag(Bool)

    public init(stringLiteral value: String) { self = .text(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .flag(value) }

    public static func int(_ value: Int) -> AnalyticsValue { .number(Double(value)) }

    var raw: Any {
        switch self {
        case .text(let value): value
        case .number(let value): value
        case .flag(let value): value
        }
    }
}
