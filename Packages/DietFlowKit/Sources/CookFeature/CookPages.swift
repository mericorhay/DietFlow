import Foundation
import SwiftUI
import DesignSystem
import Domain

// MARK: Step

/// One step, large enough to read from across the counter: what kind of step it is, the step in
/// the step's own words, and its timer when it involves waiting.
struct CookStepPage: View {
    let step: Recipe.Step
    let number: Int
    let timers: CookTimers

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var tileSize: CGFloat = 76
    @State private var appearances = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                HStack(alignment: .center, spacing: AppSpacing.medium) {
                    Image(systemName: step.kind.symbolName)
                        .font(.system(size: tileSize * 0.42, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(step.kind.tint)
                        .symbolEffect(.bounce, value: appearances)
                        .frame(width: tileSize, height: tileSize)
                        .background(step.kind.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = step.kind.name {
                            Text(verbatim: name)
                                .font(.headline)
                        }
                        if let minutes = step.minutes {
                            Text(String(localized: "cook.chip.minutes", defaultValue: "\(minutes) min", bundle: .module))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(verbatim: step.text)
                    .font(step.text.count > 160 ? Font.title3.weight(.medium) : Font.title2.weight(.medium))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let minutes = step.minutes {
                    StepTimerChip(step: number, minutes: minutes, text: step.text, timers: timers)
                }
            }
            .padding(.horizontal, AppSpacing.screenMargin)
            .padding(.vertical, AppSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if !reduceMotion { appearances += 1 }
        }
    }
}

/// A step's timer: a button to start it, then the time left counting down to an end date, then
/// "Time's up" until it is cleared.
struct StepTimerChip: View {
    let step: Int
    let minutes: Int
    let text: String
    let timers: CookTimers

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if timers.finished.contains(step) {
            finishedChip
        } else if let running = timers.running[step] {
            runningChip(running)
        } else {
            startButton
        }
    }

    private var startButton: some View {
        Button {
            timers.start(
                step: step,
                minutes: minutes,
                alertTitle: String(localized: "cook.timer.alertTitle", bundle: .module),
                alertBody: String(localized: "cook.timer.alertBody", defaultValue: "Step \(step): \(text)", bundle: .module)
            )
        } label: {
            Label {
                Text(String(localized: "cook.timer.start", defaultValue: "Start Timer · \(minutes) min", bundle: .module))
                    .monospacedDigit()
            } icon: {
                Image(systemName: "timer")
            }
            .font(.headline)
            .foregroundStyle(AppColors.brandAccent)
            .padding(.horizontal, AppSpacing.medium)
            .frame(minHeight: AppSpacing.minimumHitTarget + 8)
            .background(AppColors.brandWash, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "cook.timer.startLabel", defaultValue: "Start a \(minutes)-minute timer", bundle: .module)))
    }

    private func runningChip(_ running: CookTimers.Running) -> some View {
        HStack(spacing: AppSpacing.small) {
            Image(systemName: "timer")
                .font(.title3)
                .foregroundStyle(AppColors.brandAccent)
                .symbolEffect(.pulse, isActive: !reduceMotion)
                .accessibilityHidden(true)
            Text(timerInterval: running.interval, countsDown: true)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Button {
                timers.stop(step: step)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: AppSpacing.minimumHitTarget, height: AppSpacing.minimumHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("cook.timer.stop", bundle: .module))
        }
        .padding(.leading, AppSpacing.medium)
        .padding(.trailing, AppSpacing.xxSmall)
        .background(AppColors.brandWash, in: Capsule())
    }

    private var finishedChip: some View {
        Button {
            timers.stop(step: step)
        } label: {
            Label {
                Text("cook.timer.done", bundle: .module)
            } icon: {
                Image(systemName: "bell.fill")
                    .symbolEffect(.bounce, value: timers.finishedCount)
            }
            .font(.headline)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, AppSpacing.medium)
            .frame(minHeight: AppSpacing.minimumHitTarget + 8)
            .background(AppColors.success.opacity(0.18), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("cook.timer.doneHint", bundle: .module))
    }
}

// MARK: Finish

/// Where the last page stands on marking the meal eaten.
enum CookFinishState: Equatable {
    /// Today's or an earlier day's meal, not marked yet: "I Ate It" marks it.
    case canMark
    case eaten
    /// A later day's meal: marked on its day, not before.
    case later
    /// Skipped, or no longer in the plan: nothing to say.
    case nothing
}

/// The end of cooking: a check that draws itself, a warm word, and the meal.
struct CookFinishPage: View {
    let meal: Meal
    let isVisible: Bool
    let state: CookFinishState

    @ScaledMetric(relativeTo: .largeTitle) private var checkSize: CGFloat = 120

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: AppSpacing.large) {
                    DrawnCheck(isDrawn: isVisible || state == .eaten)
                        .frame(width: checkSize, height: checkSize)
                    VStack(spacing: AppSpacing.xSmall) {
                        Text("cook.finish.title", bundle: .module)
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("cook.finish.message", bundle: .module)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    HStack(spacing: AppSpacing.small) {
                        MealGlyph(meal.type, size: 32)
                        Text(verbatim: meal.title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, AppSpacing.medium)
                    .padding(.vertical, AppSpacing.small)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                    switch state {
                    case .eaten:
                        Label {
                            Text("cook.finish.alreadyDone", bundle: .module)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppColors.success)
                        }
                        .font(.subheadline)
                    case .later:
                        Text("cook.finish.later", bundle: .module)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    case .canMark, .nothing:
                        EmptyView()
                    }
                }
                .padding(.horizontal, AppSpacing.screenMargin)
                .padding(.vertical, AppSpacing.xLarge)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }
}

/// A ring and a tick that draw themselves when the page comes into view; drawn at once under
/// Reduce Motion.
struct DrawnCheck: View {
    let isDrawn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ring: CGFloat = 0
    @State private var tick: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(AppColors.success.opacity(0.12))
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(AppColors.success, style: StrokeStyle(lineWidth: max(4, side * 0.05), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                CheckShape()
                    .trim(from: 0, to: tick)
                    .stroke(AppColors.success, style: StrokeStyle(lineWidth: max(5, side * 0.07), lineCap: .round, lineJoin: .round))
                    .padding(side * 0.28)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
        .onAppear { update(isDrawn) }
        .onChange(of: isDrawn) { _, drawn in update(drawn) }
    }

    private func update(_ drawn: Bool) {
        guard drawn else {
            ring = 0
            tick = 0
            return
        }
        guard !reduceMotion else {
            ring = 1
            tick = 1
            return
        }
        withAnimation(.easeOut(duration: 0.5)) { ring = 1 }
        withAnimation(.easeOut(duration: 0.35).delay(0.4)) { tick = 1 }
    }
}

nonisolated private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.84))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.18))
        return path
    }
}

// MARK: Waiting

/// While the recipe is written: the meal as the plan names it, a line saying what the assistant is
/// doing, and the overview's shape behind a soft light, so the page that arrives is the page that
/// was promised.
struct CookLoadingView: View {
    let meal: Meal
    let avoids: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 56

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
                VStack(alignment: .leading, spacing: AppSpacing.small) {
                    HStack {
                        MealGlyph(meal.type, size: glyphSize)
                        Spacer(minLength: AppSpacing.small)
                        AssistantMark(.written)
                    }
                    Text(verbatim: meal.title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    ThinkingLine(lines: CookWords.thinkingLines(avoids: avoids))
                }
                skeleton
                    .assistantShimmer(true)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AppSpacing.screenMargin)
            .padding(.top, AppSpacing.small)
            .padding(.bottom, AppSpacing.xLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDisabled(true)
    }

    /// The overview's shape with stand-in words; drawn redacted, so the words never show.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
            Text(verbatim: "A filling dish with a light dressing, ready in half an hour.")
                .font(.body)
            HStack(spacing: AppSpacing.xSmall) {
                ForEach(["25 min", "Easy", "1 serving"], id: \.self) { word in
                    Text(verbatim: word)
                        .font(.subheadline)
                        .padding(.horizontal, AppSpacing.small)
                        .frame(minHeight: AppSpacing.minimumHitTarget)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                Text(verbatim: "Ingredients")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(["Chicken breast", "Romaine lettuce", "Parmesan", "Olive oil", "Lemon juice"], id: \.self) { name in
                        HStack(spacing: AppSpacing.small) {
                            Image(systemName: "circle")
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: name)
                                Text(verbatim: "150 g")
                                    .font(.subheadline)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, AppSpacing.medium)
                        .frame(minHeight: AppSpacing.minimumHitTarget + 12)
                    }
                }
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            }
        }
    }
}

/// One honest line at a time about what the assistant is doing, changing every few seconds.
struct ThinkingLine: View {
    let lines: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        Label {
            Text(verbatim: lines.isEmpty ? "" : lines[index % lines.count])
                .id(index)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "sparkles")
                .symbolEffect(.pulse, isActive: !reduceMotion)
        }
        .font(.headline)
        .foregroundStyle(AppColors.brandAccent)
        .accessibilityAddTraits(.updatesFrequently)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2_400))
                guard !Task.isCancelled else { return }
                withAppAnimation(AppMotion.settle, reduceMotion: reduceMotion) {
                    index += 1
                }
            }
        }
    }
}
