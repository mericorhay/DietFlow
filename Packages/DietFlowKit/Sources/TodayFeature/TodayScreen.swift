import Foundation
import SwiftUI
import DesignSystem

/// Today's meals in order, with the next one in front.
/// Placeholder: the real screen replaces this body.
public struct TodayScreen: View {
    public init() {}

    public var body: some View {
        Text("today.screen.title", bundle: .module)
            .font(.title2)
            .padding(DesignSystem.Spacing.medium)
    }
}
