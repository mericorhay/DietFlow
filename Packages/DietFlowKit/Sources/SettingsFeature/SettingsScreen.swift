import Foundation
import SwiftUI
import DesignSystem

/// Language, reminders, the MCP connection and the account.
/// Placeholder: the real screen replaces this body.
public struct SettingsScreen: View {
    public init() {}

    public var body: some View {
        Text("settings.screen.title", bundle: .module)
            .font(.title2)
            .padding(DesignSystem.Spacing.medium)
    }
}
