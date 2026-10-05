import Foundation
import SwiftUI
import DesignSystem

/// First launch: what the app does, then straight to getting a plan in.
/// Placeholder: the real screen replaces this body.
public struct OnboardingScreen: View {
    public init() {}

    public var body: some View {
        Text("onboarding.welcome.title", bundle: .module)
            .font(.title2)
            .padding(DesignSystem.Spacing.medium)
    }
}
