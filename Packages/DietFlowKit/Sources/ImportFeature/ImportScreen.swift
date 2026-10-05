import Foundation
import SwiftUI
import DesignSystem

/// Bringing a plan in from pasted text, a photo or a PDF.
/// Placeholder: the real screen replaces this body.
public struct ImportScreen: View {
    public init() {}

    public var body: some View {
        Text("import.screen.title", bundle: .module)
            .font(.title2)
            .padding(DesignSystem.Spacing.medium)
    }
}
