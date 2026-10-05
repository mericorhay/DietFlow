import SwiftUI
import UIKit
import Domain

/// The state of a meal as a symbol, always paired with text or a VoiceOver label elsewhere:
/// colour is never the only signal.
public struct MealStatusSymbol: View {
    public enum Status: Hashable, Sendable {
        case done
        case skipped
        /// On now.
        case current
        /// The next one up.
        case next
        case pending
        /// Its time passed without it being marked.
        case missed

        public init(_ role: MealRole) {
            switch role {
            case .done: self = .done
            case .skipped: self = .skipped
            case .current: self = .current
            case .next: self = .next
            case .upcoming: self = .pending
            case .past: self = .missed
            }
        }
    }

    private let status: Status
    private let font: Font

    public init(_ status: Status, font: Font = .title3) {
        self.status = status
        self.font = font
    }

    public var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .font(font)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHidden(true)
    }

    private var symbolName: String {
        switch status {
        case .done: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .current: "circle.inset.filled"
        case .next: "circle.circle"
        case .pending, .missed: "circle"
        }
    }

    private var color: Color {
        switch status {
        case .done: AppColors.success
        case .current, .next: AppColors.brandAccent
        case .skipped, .missed: Color.secondary
        case .pending: Color(.tertiaryLabel)
        }
    }
}

/// Time, type and name of a meal, for lists that are not the Today timeline: the plan, the import
/// review. At accessibility text sizes the time moves above the name instead of squeezing it.
public struct MealSummaryRow<Accessory: View>: View {
    private let time: Date
    private let typeLabel: String
    private let title: String
    private let note: String?
    private let noteIsWarning: Bool
    private let accessory: Accessory

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var timeColumn: CGFloat = 56

    public init(time: Date, typeLabel: String, title: String, note: String? = nil, noteIsWarning: Bool = false, @ViewBuilder accessory: () -> Accessory) {
        self.time = time
        self.typeLabel = typeLabel
        self.title = title
        self.note = note
        self.noteIsWarning = noteIsWarning
        self.accessory = accessory()
    }

    public var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xxSmall))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.small))
        HStack(spacing: AppSpacing.small) {
            layout {
                Text(time, format: .dateTime.hour().minute())
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(noteIsWarning ? Color.orange : Color.primary)
                    .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : timeColumn, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(typeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    if let note {
                        Label(note, systemImage: noteIsWarning ? "exclamationmark.triangle.fill" : "info.circle")
                            .font(.footnote)
                            .foregroundStyle(noteIsWarning ? Color.orange : Color.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.vertical, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
    }
}

extension MealSummaryRow where Accessory == EmptyView {
    public init(time: Date, typeLabel: String, title: String, note: String? = nil, noteIsWarning: Bool = false) {
        self.init(time: time, typeLabel: typeLabel, title: title, note: note, noteIsWarning: noteIsWarning) { EmptyView() }
    }
}
