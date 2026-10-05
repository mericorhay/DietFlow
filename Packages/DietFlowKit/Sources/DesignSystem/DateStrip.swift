import SwiftUI
import Domain

/// A compact week of days: weekday initial over the date. The selected day sits in a brand-accent
/// circle that glides between days; today is marked in the accent colour when not selected.
/// Used on Today and on Plan.
public struct DateStrip: View {
    private let days: [CalendarDay]
    @Binding private var selection: CalendarDay
    private let today: CalendarDay
    private let isAvailable: (CalendarDay) -> Bool

    @Namespace private var selectionSpace
    @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 36
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter isAvailable: days outside a plan can be shown dimmed; they stay selectable.
    public init(days: [CalendarDay], selection: Binding<CalendarDay>, today: CalendarDay, isAvailable: @escaping (CalendarDay) -> Bool = { _ in true }) {
        self.days = days
        self._selection = selection
        self.today = today
        self.isAvailable = isAvailable
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                dayButton(day)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func dayButton(_ day: CalendarDay) -> some View {
        let isSelected = day == selection
        let isToday = day == today
        let date = day.middayDate()
        return Button {
            withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                selection = day
            }
        } label: {
            VStack(spacing: AppSpacing.xxSmall) {
                Text(date, format: .dateTime.weekday(.narrow))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(date, format: .dateTime.day())
                    .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AppColors.onBrandAccent : (isToday ? AppColors.brandAccent : Color.primary))
                    .frame(minWidth: circleSize, minHeight: circleSize)
                    .background {
                        if isSelected {
                            Circle()
                                .fill(AppColors.brandAccent)
                                .matchedGeometryEffect(id: "selection", in: selectionSpace)
                        }
                    }
            }
            .opacity(isAvailable(day) || isSelected ? 1 : 0.45)
            .frame(maxWidth: .infinity, minHeight: AppSpacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(isToday ? Text("dateStrip.today", bundle: .module) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
