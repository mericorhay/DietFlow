import Foundation
import SwiftUI
import DesignSystem

/// What Plus adds and how to get it.
/// Placeholder: the real screen replaces this body.
public struct PaywallScreen: View {
    public init() {}

    public var body: some View {
        Text("paywall.screen.title", bundle: .module)
            .font(.title2)
            .padding(DesignSystem.Spacing.medium)
    }
}
