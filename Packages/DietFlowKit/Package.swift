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
// extension-safe API, so it gets the plan, the file it is stored in and its own views — nothing else.
let widgetModules: [String] = ["Domain", "Persistence", "WidgetUI"]

let appModules: [String] = widgetModules + [
    "AIServices", "PlanImport", "PlanSync", "MealReminders", "Purchases", "Analytics",
    "DesignSystem",
    "OnboardingFeature", "TodayFeature", "PlanFeature", "ImportFeature", "AssistantFeature", "SettingsFeature", "PaywallFeature",
]

func engine(_ name: String, _ dependencies: [Target.Dependency] = ["Domain"]) -> Target {
    .target(name: name, dependencies: dependencies, swiftSettings: concurrency)
}

func feature(_ name: String, _ dependencies: [Target.Dependency] = ["Domain", "DesignSystem"]) -> Target {
    .target(name: name, dependencies: dependencies, resources: [.process("Resources")], swiftSettings: ui)
}

let package = Package(
    name: "DietFlowKit",
    defaultLocalization: "en",
    // Must match IPHONEOS_DEPLOYMENT_TARGET in Config/Shared.xcconfig.
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "DietFlowKit", targets: appModules),
        .library(name: "DietFlowWidgetKit", targets: widgetModules),
    ],
    targets: [
        // Pure models and pure logic. Foundation only.
        engine("Domain", []),

        // Capabilities. No SwiftUI, no dependencies on each other unless listed.
        // The plan file in the App Group container: the one thing app and widget share.
        engine("Persistence"),
        // Talks to our Worker. The provider key and the system prompt live there, never in the app.
        engine("AIServices"),
        // A dietitian's list as text, photo or PDF in; a MealPlan out.
        engine("PlanImport", ["Domain", "AIServices"]),
        // The phone's side of the MCP connection: a plan Claude wrote arrives through here.
        engine("PlanSync"),
        // Local notifications at meal times.
        engine("MealReminders"),
        engine("Purchases", []),
        engine("Analytics", []),

        // What the widget draws. Nonisolated so the timeline can be built off the main actor.
        .target(name: "WidgetUI", dependencies: ["Domain"], resources: [.process("Resources")], swiftSettings: concurrency),

        // Shared UI.
        .target(name: "DesignSystem", swiftSettings: ui),

        // Features never import each other; the app target routes between them.
        feature("OnboardingFeature"),
        feature("TodayFeature"),
        feature("PlanFeature"),
        feature("ImportFeature"),
        feature("AssistantFeature"),
        feature("SettingsFeature"),
        feature("PaywallFeature"),

        .testTarget(name: "DomainTests", dependencies: ["Domain"], swiftSettings: concurrency),
    ]
)
