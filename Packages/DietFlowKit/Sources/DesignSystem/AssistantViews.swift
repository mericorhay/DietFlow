import SwiftUI
import Domain

// One look for everything the assistant does, wherever it is: a sparkles symbol and a warm
// terracotta-to-amber edge. Someone who has seen it once knows the next one is the assistant too,
// and knows what it costs before tapping (`AssistantCost`).

extension AppColors {
    /// The assistant's edge: the brand terracotta running into amber. Only on things the assistant
    /// does, never as decoration.
    public static var assistantGradient: AngularGradient {
        AngularGradient(colors: [brandAccent, .orange, brandAccent.opacity(0.7), .orange, brandAccent], center: .center)
    }
}

/// What one use of the assistant leaves, shown under its button before it is tapped: "2 uses left
/// this month", or that it is part of Plus. Nil when there is nothing worth saying (Plus, plenty left).
public enum AssistantCost: Hashable, Sendable {
    case left(Int)
    /// Used up on the free tier: the button stays, and tapping it explains Plus.
    case plus

    /// What to show for `remaining` uses on `tier`: on the free tier always, on Plus only when few are left.
    public static func caption(remaining: Int?, tier: Tier) -> AssistantCost? {
        guard let remaining else { return nil }
        if remaining <= 0 { return tier == .free ? .plus : .left(0) }
        if tier == .plus, remaining > 5 { return nil }
        return .left(remaining)
    }
}

/// A capsule button for one thing the assistant does in place: "How to Make It", "Estimate".
/// A sparkles glyph and the assistant's edge, the same everywhere; an optional caption under it says
/// what it costs.
public struct AssistantButton: View {
    private let title: Text
    private let symbol: String
    private let cost: AssistantCost?
    private let isWorking: Bool
    private let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ title: Text, symbol: String = "sparkles", cost: AssistantCost? = nil, isWorking: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.cost = cost
        self.isWorking = isWorking
        self.action = action
    }

    public var body: some View {
        VStack(spacing: AppSpacing.xxSmall) {
            Button(action: action) {
                HStack(spacing: AppSpacing.xSmall) {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: symbol)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityHidden(true)
                    }
                    title
                        .fontWeight(.semibold)
                    if cost == .plus {
                        PlusChip()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(AppColors.brandAccent)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
                .frame(minHeight: AppSpacing.minimumHitTarget)
                .background(AppColors.brandWash, in: Capsule())
                .overlay(Capsule().strokeBorder(AppColors.assistantGradient, lineWidth: 1.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            if case .left(let count) = cost {
                Text(String(localized: "assistant.cost.left", defaultValue: "\(count) uses left this month", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(costHint)
    }

    private var costHint: Text {
        switch cost {
        case .left(let count): Text(String(localized: "assistant.cost.left", defaultValue: "\(count) uses left this month", bundle: .module))
        case .plus: Text("assistant.cost.plusHint", bundle: .module)
        case nil: Text(verbatim: "")
        }
    }
}

/// The word "Plus" in a small capsule: this is part of DietFlow Plus.
public struct PlusChip: View {
    public init() {}

    public var body: some View {
        Text("assistant.cost.plusChip", bundle: .module)
            .font(.caption2.weight(.bold))
            .foregroundStyle(AppColors.onBrandAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.brandAccent, in: Capsule())
    }
}

/// One thing the assistant does, as a wide card: a symbol, what it is, a line on how, and a chevron.
/// `prominent` is the brand fill, for the one choice a screen leads with; `quiet` sits beside others.
public struct AssistantCard: View {
    public enum Style: Sendable {
        case prominent
        case quiet
    }

    private let symbol: String
    private let title: Text
    private let subtitle: Text?
    private let badge: Text?
    private let style: Style
    private let action: () -> Void

    /// - Parameter badge: a short note in a capsule, such as "2 free this month".
    public init(symbol: String = "sparkles", title: Text, subtitle: Text? = nil, badge: Text? = nil, style: Style = .quiet, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.style = style
        self.action = action
    }

    private var isProminent: Bool { style == .prominent }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: symbol)
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.headline)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        subtitle
                            .font(.subheadline)
                            .opacity(0.85)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let badge {
                        badge
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, AppSpacing.xSmall)
                            .padding(.vertical, 2)
                            .background(isProminent ? AnyShapeStyle(AppColors.onBrandAccent.opacity(0.2)) : AnyShapeStyle(AppColors.brandWash), in: Capsule())
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isProminent ? AppColors.onBrandAccent : Color.primary)
            .background(
                isProminent ? AnyShapeStyle(AppColors.brandAccent) : AnyShapeStyle(Color(.secondarySystemBackground)),
                in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
            )
            .overlay {
                if !isProminent {
                    RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                        .strokeBorder(AppColors.assistantGradient.opacity(0.6), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Marks something the assistant made: "✦ Estimated" beside figures it worked out, "✦ Written by
/// the assistant" over a recipe. Text and a symbol, never colour alone.
public struct AssistantMark: View {
    public enum Kind: Sendable {
        case estimated
        case written
    }

    private let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var body: some View {
        Label {
            switch kind {
            case .estimated: Text("assistant.mark.estimated", bundle: .module)
            case .written: Text("assistant.mark.written", bundle: .module)
            }
        } icon: {
            Image(systemName: "sparkles")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(AppColors.brandAccent)
        .labelStyle(.titleAndIcon)
    }
}

extension View {
    /// While `isActive`, draws this as a placeholder with a soft light passing over it: what the
    /// assistant is about to fill in, instead of a spinner. Still under Reduce Motion.
    public func assistantShimmer(_ isActive: Bool) -> some View {
        modifier(AssistantShimmer(isActive: isActive))
    }

    /// Asks once whether meals may be sent to the assistant, naming who reads them. `onAllow` runs
    /// after the person agrees; the caller records it (`MealAssistantModel.allowSharing`) and asks
    /// again.
    public func assistantConsent(isPresented: Binding<Bool>, onAllow: @escaping () -> Void) -> some View {
        alert(
            Text(String(localized: "assistant.consent.title", defaultValue: "Share meals with \(AssistantProvider.name)?", bundle: .module)),
            isPresented: isPresented
        ) {
            Button(action: onAllow) {
                Text("assistant.consent.allow", bundle: .module)
            }
            Button(role: .cancel) {} label: {
                Text("assistant.consent.decline", bundle: .module)
            }
        } message: {
            Text(String(
                localized: "assistant.consent.message",
                defaultValue: "To do this, the meal's name, description and portion, and any foods you said you avoid, are sent through our server to \(AssistantProvider.name), whose AI reads them. \(AppBrand.displayName) does not keep them. Nothing else about you or your plan is sent.",
                bundle: .module
            ))
        }
    }
}

private struct AssistantShimmer: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive {
            content
                .redacted(reason: .placeholder)
                .overlay {
                    if !reduceMotion {
                        PhaseAnimator([false, true]) { lit in
                            LinearGradient(colors: [.clear, AppColors.brandAccent.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                                .scaleEffect(x: 0.6, anchor: lit ? .trailing : .leading)
                        } animation: { _ in
                            .easeInOut(duration: 1.1)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(Text("assistant.working", bundle: .module))
        } else {
            content
        }
    }
}

/// A meal's sitting as a symbol on a soft, tinted circle: the face a meal has in rows, the hero and
/// the widget. The tint is the sitting's, so a day reads at a glance; the symbol carries it too.
public struct MealGlyph: View {
    private let type: MealType
    private let size: CGFloat

    public init(_ type: MealType, size: CGFloat = 32) {
        self.type = type
        self.size = size
    }

    public var body: some View {
        Image(systemName: type.symbolName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Self.tint(type))
            .frame(width: size, height: size)
            .background(Self.tint(type).opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }

    /// The sitting's colour. System colours, so they follow Dark Mode and Increase Contrast.
    public static func tint(_ type: MealType) -> Color {
        switch type {
        case .breakfast: .orange
        case .snack: .purple
        case .lunch: .green
        case .dinner: .indigo
        case .other: .gray
        }
    }
}
