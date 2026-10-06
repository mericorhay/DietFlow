import Foundation
import SwiftUI
import WidgetKit
import DesignSystem
import Domain
import WidgetUI

/// The three steps of adding a widget, in words. iOS has no way for an app to add its own widget,
/// so the introduction shows the person how.
enum AddWidgetSteps {
    static var all: [String] {
        [
            String(localized: "onboarding.add.step1", bundle: .module),
            String(localized: "onboarding.add.step2", bundle: .module),
            String(localized: "onboarding.add.step3", defaultValue: "Pick \(AppBrand.displayName)", bundle: .module),
        ]
    }
}

/// A small Home Screen on which the widget gets added, over and over: a finger touches and holds,
/// the icons start to jiggle, Edit is tapped, the icons make room and the widget lands.
struct AddWidgetPreview: View {
    let isActive: Bool
    let look: WidgetPreferences
    /// Stops the scene at this moment, to check it; nil lets it play.
    let frozenAt: TimeInterval?
    @State private var start = Date.now
    /// With Reduce Motion nothing moves: the three steps are shown as three stills, one fading
    /// into the next.
    @State private var still = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stills: [TimeInterval] = [1.35, 2.55, 6.2]

    var body: some View {
        Group {
            if let frozenAt {
                HomeScreenScene(time: frozenAt, look: look)
            } else if reduceMotion {
                HomeScreenScene(time: Self.stills[still], look: look)
                    .id(still)
                    .transition(.opacity)
            } else {
                TimelineView(.animation(minimumInterval: nil, paused: !isActive)) { context in
                    let elapsed = max(context.date.timeIntervalSince(start), 0)
                    HomeScreenScene(time: elapsed.truncatingRemainder(dividingBy: HomeScreenScene.loop), look: look)
                }
            }
        }
        .onChange(of: isActive, initial: true) { _, isActive in
            // From the beginning each time the page is come to.
            if isActive { start = .now }
        }
        .task(id: isActive) {
            guard isActive, reduceMotion, frozenAt == nil else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                guard !Task.isCancelled else { return }
                withAnimation(AppMotion.reduced) { still = (still + 1) % Self.stills.count }
            }
        }
    }
}

// MARK: - Time

/// How far `time` is from `start` to `end`: 0 before, 1 after, straight in between.
private func progress(_ time: Double, _ start: Double, _ end: Double) -> Double {
    min(max((time - start) / (end - start), 0), 1)
}

/// The same, starting and stopping gently.
private func eased(_ time: Double, _ start: Double, _ end: Double) -> Double {
    let x = progress(time, start, end)
    return x * x * (3 - 2 * x)
}

/// 0 to 1, going a little past 1 before settling: something landing.
private func landing(_ x: Double) -> Double {
    let overshoot = 1.70158
    let y = x - 1
    return 1 + (overshoot + 1) * y * y * y + overshoot * y * y
}

// MARK: - The scene

/// The sizes of the small Home Screen, all from its width, in the proportions of an iPhone's.
private struct HomeScreenMetrics {
    let width: CGFloat

    var corner: CGFloat { width * 0.14 }
    var margin: CGFloat { width * 0.07 }
    /// Four icons and three gaps of 0.45 icons fill a row.
    var icon: CGFloat { (width - 2 * margin) / 5.35 }
    var gap: CGFloat { icon * 0.45 }
    var widgetWidth: CGFloat { width - 2 * margin }
    var widgetHeight: CGFloat { widgetWidth * 170 / 364 }
    /// A medium widget stands exactly where two rows of icons would.
    var rowPitch: CGFloat { (widgetHeight + gap) / 2 }
    /// Where the first row begins, under the status bar.
    var top: CGFloat { width * 0.2 }
    var statusLine: CGFloat { width * 0.09 }
    var height: CGFloat { top + rowPitch * 7 }
    var finger: CGFloat { icon * 0.8 }

    func iconCenter(column: Int, row: Double) -> CGPoint {
        CGPoint(
            x: margin + CGFloat(column) * (icon + gap) + icon / 2,
            y: top + CGFloat(row) * rowPitch + icon / 2
        )
    }

    /// The Edit button iOS shows at the top while the icons jiggle.
    var editPoint: CGPoint {
        CGPoint(x: margin + icon * 0.62, y: statusLine)
    }

    /// An empty spot under the icons: where the finger touches and holds.
    var holdPoint: CGPoint {
        CGPoint(x: width * 0.5, y: top + 4.6 * rowPitch)
    }
}

/// The Home Screen at one moment of adding the widget. Everything is worked out from `time`, so
/// the scene can be played, stopped at any instant, or shown as a still.
struct HomeScreenScene: View {
    /// Seconds into the scene.
    let time: TimeInterval
    let look: WidgetPreferences

    /// The scene starts again after this long.
    static let loop: TimeInterval = 7.6

    private static let iconColors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .yellow, .indigo, .mint, .red, .cyan, .brown]
    private static let iconCount = 16

    var body: some View {
        GeometryReader { proxy in
            let metrics = HomeScreenMetrics(width: min(max(proxy.size.width - 2 * AppSpacing.xxLarge, 120), 300))
            phone(metrics)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .overlay(alignment: .bottom) {
                    captions
                        .padding(.horizontal, AppSpacing.medium)
                        .padding(.bottom, AppSpacing.medium)
                }
        }
    }

    // MARK: When things happen

    /// 0 while the icons are where they began, 1 once they have moved down to make room. They
    /// move first; the widget lands in the room they have made.
    private var roomMade: Double {
        eased(time, 2.9, 3.45) - eased(time, 7.0, 7.4)
    }

    /// How hard the icons jiggle: from the long press until Done.
    private var jiggleAmount: Double {
        eased(time, 1.6, 1.8) * (1 - eased(time, 5.0, 5.3))
    }

    /// Degrees, a different beat for each icon.
    private func jiggle(_ index: Int) -> Double {
        let beat = time * 2 * Double.pi * 6.5 + Double(index) * 1.7
        return 2.2 * jiggleAmount * sin(beat)
    }

    private var widgetOpacity: Double {
        eased(time, 3.2, 3.45) * (1 - eased(time, 6.9, 7.2))
    }

    private var widgetScale: Double {
        0.55 + 0.45 * landing(progress(time, 3.2, 3.95))
    }

    private var editOpacity: Double {
        eased(time, 1.6, 1.75) * (1 - eased(time, 5.0, 5.3))
    }

    private var editScale: Double {
        landing(progress(time, 1.6, 1.95)) * (1 - 0.14 * tapPress)
    }

    /// 1 while the finger is pressed on the empty spot.
    private var holdPress: Double {
        eased(time, 0.95, 1.1) * (1 - eased(time, 1.6, 1.75))
    }

    /// 1 at the moment the finger taps Edit.
    private var tapPress: Double {
        eased(time, 2.4, 2.5) * (1 - eased(time, 2.6, 2.72))
    }

    private var fingerOpacity: Double {
        eased(time, 0.6, 0.85) * (1 - eased(time, 2.85, 3.1))
    }

    /// 0 on the empty spot, 1 on Edit.
    private var fingerTravel: Double {
        eased(time, 1.75, 2.35)
    }

    private var doneScale: Double {
        landing(progress(time, 5.35, 5.75)) * (1 - eased(time, 6.9, 7.1))
    }

    // MARK: The phone

    private func phone(_ metrics: HomeScreenMetrics) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
        return ZStack {
            // The wallpaper, in the colour that was chosen.
            shape.fill(Color(.systemBackground))
            shape.fill(LinearGradient(
                colors: [look.accent.fill.opacity(0.42), look.accent.fill.opacity(0.14)],
                startPoint: .top,
                endPoint: .bottom
            ))
            Capsule()
                .fill(Color.black.opacity(0.85))
                .frame(width: metrics.width * 0.28, height: metrics.width * 0.075)
                .position(x: metrics.width / 2, y: metrics.statusLine)
            icons(metrics)
            widget(metrics)
            editButton(metrics)
            finger(metrics)
        }
        .frame(width: metrics.width, height: metrics.height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
        .padding(.top, AppSpacing.xLarge)
    }

    private func icons(_ metrics: HomeScreenMetrics) -> some View {
        ForEach(0..<Self.iconCount, id: \.self) { index in
            RoundedRectangle(cornerRadius: metrics.icon * 0.23, style: .continuous)
                .fill(Self.iconColors[index % Self.iconColors.count].gradient)
                .opacity(0.82)
                .frame(width: metrics.icon, height: metrics.icon)
                .rotationEffect(.degrees(jiggle(index)))
                .position(metrics.iconCenter(column: index % 4, row: Double(index / 4) + 2 * roomMade))
        }
    }

    private func widget(_ metrics: HomeScreenMetrics) -> some View {
        let fit = metrics.widgetWidth / StagedWidget.size(.systemMedium).width
        let centerY = metrics.top + metrics.widgetHeight / 2
        return ZStack {
            StagedWidget(kind: .nextMeal, family: .systemMedium, minute: 13 * 60 + 18, look: look)
                .scaleEffect(fit * CGFloat(widgetScale))
                .rotationEffect(.degrees(jiggle(Self.iconCount) * 0.3))
                .opacity(widgetOpacity)
                .frame(width: metrics.widgetWidth, height: metrics.widgetHeight)
                .position(x: metrics.width / 2, y: centerY)
            // Done: the widget is on the Home Screen.
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: metrics.icon * 0.66))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, AppColors.success)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .scaleEffect(CGFloat(max(doneScale, 0)))
                .position(x: metrics.margin + metrics.widgetWidth - metrics.icon * 0.12, y: metrics.top + metrics.icon * 0.12)
        }
    }

    private func editButton(_ metrics: HomeScreenMetrics) -> some View {
        Text("onboarding.add.edit", bundle: .module)
            .font(.system(size: metrics.icon * 0.3, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, metrics.icon * 0.26)
            .padding(.vertical, metrics.icon * 0.12)
            .background(.regularMaterial, in: Capsule())
            .scaleEffect(CGFloat(max(editScale, 0)))
            .opacity(editOpacity)
            .position(metrics.editPoint)
    }

    private func finger(_ metrics: HomeScreenMetrics) -> some View {
        let hold = metrics.holdPoint
        let edit = metrics.editPoint
        let travel = CGFloat(fingerTravel)
        let point = CGPoint(x: hold.x + (edit.x - hold.x) * travel, y: hold.y + (edit.y - hold.y) * travel)
        let holdRipple = progress(time, 1.0, 1.6)
        let tapRipple = progress(time, 2.45, 2.9)
        return ZStack {
            ripple(holdRipple, size: metrics.finger).position(hold)
            ripple(tapRipple, size: metrics.finger).position(edit)
            Circle()
                .fill(Color.primary.opacity(0.28))
                .overlay { Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2) }
                .frame(width: metrics.finger, height: metrics.finger)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .scaleEffect(CGFloat(1 - 0.2 * max(holdPress, tapPress)))
                .opacity(fingerOpacity)
                .position(point)
        }
    }

    /// A ring spreading from where the finger presses.
    private func ripple(_ amount: Double, size: CGFloat) -> some View {
        Circle()
            .strokeBorder(Color.primary.opacity(0.4), lineWidth: 2)
            .frame(width: size, height: size)
            .scaleEffect(CGFloat(1 + 1.5 * amount))
            .opacity(amount > 0 && amount < 1 ? 1 - amount : 0)
    }

    // MARK: The steps

    private var captions: some View {
        let steps = AddWidgetSteps.all
        return ZStack {
            caption(1, steps[0], from: 0.5, to: 1.9)
            caption(2, steps[1], from: 1.9, to: 3.0)
            caption(3, steps[2], from: 3.0, to: 7.1)
        }
    }

    private func caption(_ number: Int, _ text: String, from start: Double, to end: Double) -> some View {
        let visible = eased(time, start, start + 0.25) * (1 - eased(time, end - 0.2, end))
        return HStack(spacing: AppSpacing.xSmall) {
            Text(number, format: .number)
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(look.accent.fill))
            Text(verbatim: text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.leading, AppSpacing.xSmall)
        .padding(.trailing, AppSpacing.medium)
        .padding(.vertical, AppSpacing.xSmall)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .opacity(visible)
        .offset(y: CGFloat(1 - visible) * 12)
    }
}
