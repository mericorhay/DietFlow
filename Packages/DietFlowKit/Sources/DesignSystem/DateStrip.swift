import SwiftUI
import Domain

/// A compact week of days: the abbreviated weekday over the date. The selected day sits in a
/// brand-accent circle that glides between days; today is marked in the accent colour when not
/// selected. Used on Today and on Plan.
public struct DateStrip: View {
    private let days: [CalendarDay]
    @Binding private var selection: CalendarDay
    private let today: CalendarDay
    private let isAvailable: (CalendarDay) -> Bool

    @Namespace private var selectionSpace
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
                DateStripDay(
                    date: day.middayDate(),
                    isSelected: day == selection,
                    isToday: day == today,
                    isAvailable: isAvailable(day),
                    selectionSpace: selectionSpace
                ) {
                    withAppAnimation(AppMotion.snappy, reduceMotion: reduceMotion) {
                        selection = day
                    }
                }
            }
        }
        // Seven days must share one row, like a tab bar: past the largest standard size the
        // strip stops growing. VoiceOver reads each day's full date.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .contain)
    }
}

/// One day of the strip. Its own view so that the circle's scaled size is read inside the strip's
/// text-size cap: read outside it, the circle kept growing at accessibility sizes and pushed the
/// week, and the whole page with it, past both edges of the screen.
private struct DateStripDay: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isAvailable: Bool
    let selectionSpace: Namespace.ID
    let action: @MainActor () -> Void

    @ScaledMetric(relativeTo: .body) private var circleSize: CGFloat = 36

    /// Seven of these always fit across an iPhone inside the screen's margins.
    private var circle: CGFloat { min(circleSize, AppSpacing.minimumHitTarget) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xxSmall) {
                Text(date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(date, format: .dateTime.day())
                    .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? AppColors.onBrandAccent : (isToday ? AppColors.brandAccent : Color.primary))
                    .frame(minWidth: circle, minHeight: circle)
                    .background {
                        if isSelected {
                            Circle()
                                .fill(AppColors.brandAccent)
                                .matchedGeometryEffect(id: "selection", in: selectionSpace)
                        }
                    }
            }
            .opacity(isAvailable || isSelected ? 1 : 0.45)
            .frame(maxWidth: .infinity, minHeight: AppSpacing.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(date, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(isToday ? Text("dateStrip.today", bundle: .module) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
