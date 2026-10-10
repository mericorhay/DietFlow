// swift-tools-version: 6.2
import PackageDescription

// Swift 6 language mode is the default for tools 6.x.
// Domain and engines stay nonisolated; UI modules default to the main actor.
let concurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]
let ui: [SwiftSetting] = concurrency + [.defaultIsolation(MainActor.self)]

// What the widget extension links. It runs in a tight memory budget and may only use
// extension-safe API: the plan logic, the shared files, the store its Done button writes through,
// and its own views — nothing else.
let widgetModules: [String] = ["Domain", "Persistence", "MealReminders", "AppCore", "DesignSystem", "WidgetUI"]

let appModules: [String] = widgetModules + [
    "AIServices", "PlanImport", "PlanSync", "Purchases", "Analytics",
    "OnboardingFeature", "TodayFeature", "PlanFeature", "MealFeature", "CookFeature", "ImportFeature", "WidgetsFeature",
    "AssistantFeature", "SettingsFeature", "PaywallFeature",
]

func engine(_ name: String, _ dependencies: [Target.Dependency] = ["Domain"], resources: [Resource]? = nil) -> Target {
    .target(name: name, dependencies: dependencies, resources: resources, swiftSettings: concurrency)
}

func feature(_ name: String, _ dependencies: [Target.Dependency] = ["Domain", "DesignSystem", "AppCore"]) -> Target {
    .target(name: name, dependencies: dependencies, resources: [.process("Resources")], swiftSettings: ui)
}

let package = Package(
    name: "DietFlowKit",
    defaultLocalization: "en",
    // Must match IPHONEOS_DEPLOYMENT_TARGET in Config/Shared.xcconfig.
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "DietFlowKit", targets: appModules),
        .library(name: "DietFlowWidgetKit", targets: widgetModules),
    ],
    dependencies: [
        // Product analytics. Only the Analytics module sees it.
        .package(url: "https://github.com/PostHog/posthog-ios.git", from: "3.0.0"),
    ],
    targets: [
        // Pure models and pure logic: the schedule, the widget timeline, the import format.
        // Foundation only; its strings are meal type names and relative times.
        engine("Domain", [], resources: [.process("Resources")]),

        // Capabilities. No SwiftUI, no dependencies on each other unless listed.
        // The SwiftData store and the files the app and the widget share in the App Group.
        engine("Persistence"),
        // Local notifications at meal times.
        engine("MealReminders", resources: [.process("Resources")]),
        // The one place plans change: storage, then the widget snapshot, widget reload and reminders.
        // What the screens, the App Intents and a future MCP bridge all call.
        engine("AppCore", ["Domain", "Persistence", "MealReminders"]),
        // A plan as pasted text, a file, a photo or a PDF in; a draft for review out. On device.
        engine("PlanImport"),
        // The plan assistant: talks to our Worker, which holds the provider key and the prompts.
        engine("AIServices"),
        // The phone's side of a future MCP connection.
        engine("PlanSync"),
        // DietFlow Plus through StoreKit. App only: the widget never asks what was bought.
        engine("Purchases"),
        // Which features are used and where people stop. Nothing the person wrote leaves in it.
        engine("Analytics", [.product(name: "PostHog", package: "posthog-ios")]),

        // Shared UI. Nonisolated so the widget can use the same tokens off the main actor.
        .target(name: "DesignSystem", dependencies: ["Domain"], resources: [.process("Resources")], swiftSettings: concurrency),
        // What the widget draws, also shown on the Widgets tab and in onboarding.
        .target(name: "WidgetUI", dependencies: ["Domain", "DesignSystem"], resources: [.process("Resources")], swiftSettings: concurrency),

        // Features never import each other; the app target routes between them.
        feature("OnboardingFeature", ["Domain", "DesignSystem", "AppCore", "WidgetUI"]),
        feature("TodayFeature"),
        feature("PlanFeature"),
        feature("MealFeature"),
        // Cooking a meal step by step. Reaches the assistant through AppCore's MealAssistantModel.
        feature("CookFeature"),
        feature("ImportFeature", ["Domain", "DesignSystem", "AppCore", "PlanImport", "AIServices", "Analytics"]),
        feature("WidgetsFeature", ["Domain", "DesignSystem", "AppCore", "WidgetUI"]),
        feature("SettingsFeature", ["Domain", "DesignSystem", "AppCore", "Purchases", "Analytics"]),
        feature("AssistantFeature", ["Domain", "DesignSystem"]),
        feature("PaywallFeature", ["Domain", "DesignSystem", "Purchases", "Analytics"]),

        .testTarget(name: "DomainTests", dependencies: ["Domain"], swiftSettings: concurrency),
    ]
)
