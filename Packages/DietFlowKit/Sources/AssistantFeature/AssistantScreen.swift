import Foundation
import SwiftUI
import DesignSystem

/// Chat with the built-in assistant; it can propose a plan for the person to accept.
/// Placeholder: the real screen replaces this body.
public struct AssistantScreen: View {
    public init() {}

    public var body: some View {
        Text("assistant.screen.title", bundle: .module)
            .font(.title2)
            .padding(DesignSystem.Spacing.medium)
    }
}
