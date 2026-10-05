import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AppCore
import DesignSystem
import Domain
import PlanImport

/// Something handed to Import from outside the screen: text from the Import Plan shortcut, or a
/// file opened with the app from Files, Mail or AirDrop.
public enum ImportInput: Sendable {
    case text(String)
    case file(Data, fileName: String)
}

/// Bringing in a plan the person already has: pasted text, a file, a photo or a PDF. Whatever the
/// source, the plan is read on the device and always shown for review before anything is saved.
public struct ImportPlanScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var path: [ImportRoute] = []
    @State private var isReading = false
    @State private var failure: ImportFailure?
    @State private var copiedInstructions = false
    @State private var fileRequest: FileRequest?
    @State private var showsPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    private let initialInput: ImportInput?
    private let onFinished: () -> Void
    private let service = MealPlanImportService()

    /// - Parameters:
    ///   - initialInput: text or a file handed over from outside, read straight away.
    ///   - onFinished: called after a plan is saved.
    public init(initialInput: ImportInput? = nil, onFinished: @escaping () -> Void) {
        self.initialInput = initialInput
        self.onFinished = onFinished
    }

    public var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Text("import.intro", bundle: .module)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: AppSpacing.xxSmall, bottom: 0, trailing: AppSpacing.xxSmall))
                }

                Section {
                    NavigationLink(value: ImportRoute.paste) {
                        SourceRow(symbol: "doc.on.clipboard", title: "import.paste.title", subtitle: "import.paste.subtitle")
                    }
                    Button {
                        fileRequest = .plan
                    } label: {
                        SourceRow(symbol: "doc", title: "import.file.title", subtitle: "import.file.subtitle")
                    }
                    .foregroundStyle(.primary)
                    Menu {
                        Button {
                            showsPhotoPicker = true
                        } label: {
                            Label { Text("import.scan.photo", bundle: .module) } icon: { Image(systemName: "photo") }
                        }
                        Button {
                            fileRequest = .pdf
                        } label: {
                            Label { Text("import.scan.pdf", bundle: .module) } icon: { Image(systemName: "doc.richtext") }
                        }
                    } label: {
                        SourceRow(symbol: "doc.viewfinder", title: "import.scan.title", subtitle: "import.scan.subtitle")
                    }
                    .foregroundStyle(.primary)
                }

                Section {
                    Button(action: copyInstructions) {
                        Label {
                            Text(copiedInstructions ? "import.ai.copied" : "import.ai.copy", bundle: .module)
                        } icon: {
                            Image(systemName: copiedInstructions ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .tint(AppColors.brandAccent)
                } header: {
                    Text("import.ai.header", bundle: .module)
                } footer: {
                    Text("import.ai.footer", bundle: .module)
                }
            }
            .navigationTitle(Text("import.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("import.cancel", bundle: .module)
                    }
                }
            }
            .navigationDestination(for: ImportRoute.self) { route in
                switch route {
                case .paste:
                    PastePlanScreen { text in
                        await read(.text(text))
                    }
                case .review(let draft):
                    ImportReviewScreen(draft: draft, onSave: save)
                }
            }
            .disabled(isReading)
            .overlay {
                if isReading {
                    ProgressView {
                        Text("import.reading", bundle: .module)
                    }
                    .padding(AppSpacing.xLarge)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                }
            }
        }
        .fileImporter(
            isPresented: Binding(get: { fileRequest != nil }, set: { if !$0 { fileRequest = nil } }),
            allowedContentTypes: fileRequest?.contentTypes ?? FileRequest.plan.contentTypes
        ) { result in
            let request = fileRequest ?? .plan
            Task { await readFile(result, as: request) }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await readPhoto(item) }
        }
        .alert(Text("import.error.title", bundle: .module), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }), presenting: failure) { _ in
            Button(role: .cancel) {} label: { Text("import.error.ok", bundle: .module) }
        } message: { failure in
            Text(failure.message)
        }
        .task {
            switch initialInput {
            case .text(let text):
                await read(.text(text))
            case .file(let data, let fileName):
                await read(fileName.lowercased().hasSuffix(".pdf") ? .pdf(data) : .file(data))
            case nil:
                break
            }
        }
    }

    // MARK: Reading

    private func read(_ source: PlanSource) async {
        isReading = true
        defer { isReading = false }
        let defaults = ImportDefaults(planName: String(localized: "import.defaultPlanName", bundle: .module), startDay: .today())
        do {
            let draft = try await service.importPlan(from: source, defaults: defaults)
            path.append(.review(draft))
        } catch {
            failure = ImportFailure(error)
        }
    }

    private func readFile(_ result: Result<URL, any Error>, as request: FileRequest) async {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            failure = ImportFailure(PlanImportError.unreadable)
            return
        }
        await read(request == .pdf || url.pathExtension.lowercased() == "pdf" ? .pdf(data) : .file(data))
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            failure = ImportFailure(PlanReadingError.noTextFound)
            return
        }
        await read(.image(data))
    }

    // MARK: Saving

    private func save(_ plan: MealPlan) {
        store.attempt { try store.createPlan(plan, activate: true) }
        dismiss()
        onFinished()
    }

    private func copyInstructions() {
        UIPasteboard.general.string = MealPlanPayload.aiInstructions
        withAnimation(AppMotion.snappy) { copiedInstructions = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(AppMotion.snappy) { copiedInstructions = false }
        }
    }
}

enum ImportRoute: Hashable {
    case paste
    case review(ImportedPlanDraft)
}

private enum FileRequest: Hashable {
    case plan
    case pdf

    var contentTypes: [UTType] {
        switch self {
        case .plan:
            return [.mealPlan, .json, .plainText]
        case .pdf:
            return [.pdf]
        }
    }
}

/// Why an import stopped, in words the person can act on.
struct ImportFailure: Identifiable {
    let id = UUID()
    let message: String

    init(_ error: any Error) {
        switch error {
        case PlanImportError.empty:
            message = String(localized: "import.error.empty", bundle: .module)
        case PlanImportError.noMeals:
            message = String(localized: "import.error.noMeals", bundle: .module)
        case PlanImportError.unreadable:
            message = String(localized: "import.error.unreadable", bundle: .module)
        case PlanReadingError.noTextFound:
            message = String(localized: "import.error.noText", bundle: .module)
        default:
            message = String(localized: "import.error.generic", bundle: .module)
        }
    }
}

/// A way in: a symbol, what it is, and a line saying what it takes.
private struct SourceRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: AppSpacing.medium) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(AppColors.brandAccent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title, bundle: .module)
                    .font(.body)
                Text(subtitle, bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AppSpacing.xxSmall)
        .accessibilityElement(children: .combine)
    }
}

/// A plan pasted from ChatGPT, Claude, a dietitian's message or a note.
struct PastePlanScreen: View {
    let onContinue: (String) async -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .focused($isFocused)
            .font(.body)
            .padding(.horizontal, AppSpacing.medium)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("import.paste.placeholder", bundle: .module)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, AppSpacing.large)
                        .padding(.vertical, AppSpacing.xSmall)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle(Text("import.paste.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in
                            text = strings.joined(separator: "\n")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isFocused = false
                        Task { await onContinue(text) }
                    } label: {
                        Text("import.paste.continue", bundle: .module)
                    }
                    .disabled(text.trimmedNonEmpty == nil)
                }
            }
            .onAppear { isFocused = true }
    }
}
