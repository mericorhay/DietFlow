import SwiftUI
import AppCore

@main
struct DietFlowApp: App {
    @State private var dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
                .environment(dependencies.store)
                .environment(dependencies.access)
                .environment(dependencies.plus)
        }
    }
}
