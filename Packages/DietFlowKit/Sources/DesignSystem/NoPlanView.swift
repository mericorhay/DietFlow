import SwiftUI

/// What Today and Plan show before any plan exists: one sentence and the ways to get a plan.
/// Where the build has the assistant it comes first, since it is the quickest way from nothing to
/// a plan: say how you eat, or paste the list you have. Left-aligned and small, with a restrained
/// symbol rather than an illustration.
public struct NoPlanView: View {
    private let onCreate: () -> Void
    private let onImport: () -> Void
    private let onWritePlan: (() -> Void)?
    private let onOrganizeList: (() -> Void)?

    /// - Parameters:
    ///   - onWritePlan: asks the assistant to write a plan; nil in a build without the assistant.
    ///   - onOrganizeList: asks the assistant to put a pasted list in order; nil likewise.
    public init(
        onCreate: @escaping () -> Void,
        onImport: @escaping () -> Void,
        onWritePlan: (() -> Void)? = nil,
        onOrganizeList: (() -> Void)? = nil
    ) {
        self.onCreate = onCreate
        self.onImport = onImport
        self.onWritePlan = onWritePlan
        self.onOrganizeList = onOrganizeList
    }

    private var hasAssistant: Bool {
        onWritePlan != nil || onOrganizeList != nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Image(systemName: "calendar.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("noPlan.title", bundle: .module)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("noPlan.message", bundle: .module)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if hasAssistant {
                VStack(spacing: AppSpacing.xSmall) {
                    if let onWritePlan {
                        AssistantCard(
                            symbol: "sparkles",
                            title: Text("noPlan.write.title", bundle: .module),
                            subtitle: Text("noPlan.write.subtitle", bundle: .module),
                            style: .prominent,
                            action: onWritePlan
                        )
                    }
                    if let onOrganizeList {
                        AssistantCard(
                            symbol: "wand.and.stars",
                            title: Text("noPlan.organize.title", bundle: .module),
                            subtitle: Text("noPlan.organize.subtitle", bundle: .module),
                            style: .quiet,
                            action: onOrganizeList
                        )
                    }
                }
                .padding(.top, AppSpacing.xSmall)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.small) { buttons }
                VStack(alignment: .leading, spacing: AppSpacing.small) { buttons }
            }
            .padding(.top, AppSpacing.xSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.screenMargin)
    }

    @ViewBuilder
    private var buttons: some View {
        // With the assistant in front, doing it by hand is the quieter choice.
        if hasAssistant {
            Button(action: onCreate) {
                Text("noPlan.create", bundle: .module)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Button(action: onCreate) {
                Text("noPlan.create", bundle: .module)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.brandAccent)
            .controlSize(.large)
        }

        Button(action: onImport) {
            Text("noPlan.import", bundle: .module)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
