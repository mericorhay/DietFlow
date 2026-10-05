import SwiftUI

/// What Today and Plan show before any plan exists: one sentence and the two ways to get a plan.
/// Left-aligned and small, with a restrained symbol rather than an illustration.
public struct NoPlanView: View {
    private let onCreate: () -> Void
    private let onImport: () -> Void
    private let onTrySample: (() -> Void)?

    /// - Parameter onTrySample: loads the sample plan, for a look around before writing one.
    public init(onCreate: @escaping () -> Void, onImport: @escaping () -> Void, onTrySample: (() -> Void)? = nil) {
        self.onCreate = onCreate
        self.onImport = onImport
        self.onTrySample = onTrySample
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.small) { buttons }
                VStack(alignment: .leading, spacing: AppSpacing.small) { buttons }
            }
            .padding(.top, AppSpacing.xSmall)
            if let onTrySample {
                Button(action: onTrySample) {
                    Text("noPlan.trySample", bundle: .module)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: AppSpacing.minimumHitTarget)
                }
                .buttonStyle(.borderless)
                .tint(AppColors.brandAccent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.screenMargin)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(action: onCreate) {
            Text("noPlan.create", bundle: .module)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.brandAccent)
        .controlSize(.large)

        Button(action: onImport) {
            Text("noPlan.import", bundle: .module)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
