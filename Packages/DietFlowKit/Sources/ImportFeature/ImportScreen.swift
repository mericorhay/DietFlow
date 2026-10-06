import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import AIServices
import Analytics
import AppCore
import DesignSystem
import Domain
import PlanImport

/// Something handed to Import from outside the screen: text from the Import Plan shortcut, or a
/// file opened with the app from Files, Mail or AirDrop.
public enum ImportInput: Sendable {
    case text(String)
    case file(Data, fileName: String)
    /// A file that could not be read, or is far larger than a plan can be. Import says so.
    case unreadableFile

    /// Reads a file handed to the app, refusing one too large to be a plan before any of it is
    /// loaded: a file opened by mistake must not be able to exhaust the app's memory.
    public static func reading(fileAt url: URL) -> ImportInput {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let isPDF = url.pathExtension.lowercased() == "pdf"
        let limit = isPDF ? PlanLimits.importDocumentBytes : PlanLimits.importFileBytes
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= limit,
              let data = try? Data(contentsOf: url) else {
            return .unreadableFile
        }
        return .file(data, fileName: url.lastPathComponent)
    }
}

/// Where Import Plan opens. The assistant is reached from the first screens of the app, and
/// from there it should be one tap to what was asked for, not a list to choose from again.
public enum ImportStart: Sendable {
    /// Every way in, as a list.
    case sources
    /// The assistant putting a pasted list in order.
    case organize
    /// The assistant writing a new plan.
    case create
}

/// Getting a plan in: one the person already has, as pasted text, a file, a photo or a PDF, read on
/// the device; or, with the assistant, any list however untidy put in order, or a new plan written
/// from a few wishes. Whatever the source, the plan is always shown for review before it is saved.
public struct ImportPlanScreen: View {
    @Environment(MealPlanStore.self) private var store
    @Environment(AccessModel.self) private var access
    @Environment(\.dismiss) private var dismiss
    @State private var path: [ImportRoute] = []
    @State private var isReading = false
    /// The assistant is working: a longer wait than reading on the device, and worded as one.
    @State private var isAsking = false
    /// The reading or the request under way. There is only ever one: a second tap while it runs
    /// must not start a second, and Cancel has to be able to stop it.
    @State private var work: Task<Void, Never>?
    @State private var didReadInitialInput = false
    @State private var didSave = false
    /// A request waiting for the person to agree that its text goes to the AI company.
    @State private var consent: AssistantConsent?
    /// How the plan on the review screen came in, for the event sent when it is saved.
    @State private var lastSource = "unknown"
    @State private var failure: ImportFailure?
    @State private var copiedInstructions = false
    @State private var fileRequest: FileRequest?
    @State private var showsPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    private let initialInput: ImportInput?
    private let assistant: PlanAssistantClient?
    private let onFinished: () -> Void
    private let service = MealPlanImportService()

    /// - Parameters:
    ///   - initialInput: text or a file handed over from outside, read straight away.
    ///   - assistant: the plan assistant, or nil in a build without one; its rows are then left out.
    ///   - start: the screen shown first. Back from it leads to the list of every way in.
    ///   - onFinished: called after a plan is saved.
    public init(initialInput: ImportInput? = nil, assistant: PlanAssistantClient? = nil, start: ImportStart = .sources, onFinished: @escaping () -> Void) {
        self.initialInput = initialInput
        self.assistant = assistant
        if assistant != nil {
            switch start {
            case .sources: break
            case .organize: _path = State(initialValue: [.assistantOrganize])
            case .create: _path = State(initialValue: [.assistantCreate])
            }
        }
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

                if assistant != nil {
                    Section {
                        NavigationLink(value: ImportRoute.assistantOrganize) {
                            SourceRow(symbol: "wand.and.stars", title: "import.assistant.organize.title", subtitle: "import.assistant.organize.subtitle")
                        }
                        NavigationLink(value: ImportRoute.assistantCreate) {
                            SourceRow(symbol: "sparkles", title: "import.assistant.create.title", subtitle: "import.assistant.create.subtitle")
                        }
                    } header: {
                        Text("import.assistant.header", bundle: .module)
                    } footer: {
                        Text(verbatim: assistantFooter)
                    }
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
                        run { await read(.text(text)) }
                    }
                case .assistantOrganize:
                    PastePlanScreen(title: "import.assistant.organize.title", placeholder: "import.assistant.organize.placeholder", characterLimit: PlanAssistantClient.textLimit) { text in
                        askAssistant { await organizeWithAssistant(text) }
                    }
                case .assistantCreate:
                    AssistantPlanScreen { wishes in
                        askAssistant { await createWithAssistant(wishes) }
                    }
                case .review(let draft):
                    ImportReviewScreen(draft: draft, onSave: save)
                }
            }
        }
        // On the whole stack, not on the first screen: the wait starts from the screens pushed
        // on top of it, and that is where it has to show and where a second tap has to be stopped.
        .disabled(isReading)
        .overlay {
            if isReading {
                VStack(spacing: AppSpacing.medium) {
                    ProgressView {
                        Text(isAsking ? "import.assistant.working" : "import.reading", bundle: .module)
                            .multilineTextAlignment(.center)
                    }
                    Button(role: .cancel) {
                        work?.cancel()
                    } label: {
                        Text("import.working.cancel", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(AppSpacing.xLarge)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
                .padding(AppSpacing.xLarge)
            }
        }
        .interactiveDismissDisabled(isReading)
        .onDisappear { work?.cancel() }
        .fileImporter(
            isPresented: Binding(get: { fileRequest != nil }, set: { if !$0 { fileRequest = nil } }),
            allowedContentTypes: fileRequest?.contentTypes ?? FileRequest.plan.contentTypes
        ) { result in
            let request = fileRequest ?? .plan
            run { await readFile(result, as: request) }
        }
        .photosPicker(isPresented: $showsPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            run { await readPhoto(item) }
        }
        .alert(Text("import.error.title", bundle: .module), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }), presenting: failure) { _ in
            Button(role: .cancel) {} label: { Text("import.error.ok", bundle: .module) }
        } message: { failure in
            Text(failure.message)
        }
        .alert(
            Text(String(localized: "import.assistant.consent.title", defaultValue: "Send this to \(AssistantProvider.name)?", bundle: .module)),
            isPresented: Binding(get: { consent != nil }, set: { if !$0 { consent = nil } }),
            presenting: consent
        ) { consent in
            Button {
                store.updateSettings { $0.allowsAssistantSharing = true }
                run(asking: true, consent.request)
            } label: {
                Text("import.assistant.consent.allow", bundle: .module)
            }
            Button(role: .cancel) {} label: { Text("import.assistant.consent.decline", bundle: .module) }
        } message: { _ in
            Text(String(localized: "import.assistant.consent.message", defaultValue: "To write your plan, the text you entered is sent through our server to \(AssistantProvider.name), whose AI reads it. \(AppBrand.displayName) does not store it. Leave out anything you would not want shared.", bundle: .module))
        }
        .onAppear {
            // Once: coming back from a picker must not read what was handed over a second time.
            guard !didReadInitialInput else { return }
            didReadInitialInput = true
            switch initialInput {
            case .text(let text):
                run { await read(.text(text)) }
            case .file(let data, let fileName):
                run { await read(fileName.lowercased().hasSuffix(".pdf") ? .pdf(data) : .file(data)) }
            case .unreadableFile:
                failure = ImportFailure(PlanImportError.unreadable)
            case nil:
                break
            }
        }
    }

    // MARK: Reading

    /// Starts a reading or a request, unless one is already running. The wait shows from the tap,
    /// not from whenever the work gets going.
    private func run(asking: Bool = false, _ operation: @escaping @MainActor () async -> Void) {
        guard work == nil else { return }
        isReading = true
        isAsking = asking
        work = Task {
            await operation()
            isReading = false
            isAsking = false
            work = nil
        }
    }

    /// Shows a plan for review. Only ever one review on the stack: Back from it leads to what was
    /// typed, not to an earlier reading of it.
    private func review(_ draft: ImportedPlanDraft) {
        path.removeAll { route in
            if case .review = route { true } else { false }
        }
        path.append(.review(draft))
    }

    private func read(_ source: PlanSource) async {
        let defaults = ImportDefaults(planName: String(localized: "import.defaultPlanName", bundle: .module), startDay: .today())
        do {
            let draft = try await service.importPlan(from: source, defaults: defaults)
            guard !Task.isCancelled else { return }
            report(source.analyticsName, draft: draft)
            review(draft)
        } catch {
            guard !Task.isCancelled else { return }
            Analytics.track("plan_import_failed", ["source": .text(source.analyticsName), "reason": .text(analyticsReason(error))])
            failure = ImportFailure(error)
        }
    }

    /// The shape of what was read: how it came in and how big it is. Never what is in it.
    private func report(_ source: String, draft: ImportedPlanDraft) {
        lastSource = source
        Analytics.track("plan_imported", [
            "source": .text(source),
            "days": .int(draft.plan.schedule.length),
            "meals": .int(draft.plan.meals.count),
            "issues": .int(draft.issues.count),
        ])
    }

    // MARK: The assistant

    /// Sends a request to the assistant, once the person has agreed to where its text goes. The
    /// first time, and whenever that has been switched off in Settings, they are asked; nothing
    /// leaves the phone until they say yes.
    private func askAssistant(_ request: @escaping @MainActor () async -> Void) {
        if store.settings.allowsAssistantSharing {
            run(asking: true, request)
        } else {
            consent = AssistantConsent(request: request)
        }
    }

    /// "2 of 2 left. They come back on 1 November.", then whose AI it is and what happens to the text.
    private var assistantFooter: String {
        var lines: [String] = []
        if let limit = access.limit(.aiPlan), let left = access.remaining(.aiPlan) {
            let date = access.resetsAt.formatted(.dateTime.day().month(.wide))
            lines.append(String(localized: "import.assistant.allowance", defaultValue: "\(left) of \(limit) left. They come back on \(date).", bundle: .module))
        }
        lines.append(String(localized: "import.assistant.privacy", defaultValue: "The assistant is powered by \(AssistantProvider.name). What you give it is sent there through our server to be read. We do not store it.", bundle: .module))
        return lines.joined(separator: "\n")
    }

    private func organizeWithAssistant(_ text: String) async {
        await ask("assistant_organize") { assistant in try await assistant.organize(text: text) }
    }

    private func createWithAssistant(_ wishes: PlanWishes) async {
        await ask("assistant_create") { assistant in try await assistant.create(wishes) }
    }

    /// One request to the assistant, counted against the allowance. A request that fails for any
    /// reason is given back: the allowance is only spent on a plan the person got to see.
    private func ask(_ source: String, _ request: (PlanAssistantClient) async throws -> MealPlanPayload) async {
        guard let assistant else { return }
        // Refused, the access model records why and the app shows what Plus adds.
        guard access.use(.aiPlan) else { return }
        let defaults = ImportDefaults(planName: String(localized: "import.defaultPlanName", bundle: .module), startDay: .today())
        do {
            let payload = try await request(assistant)
            // The same checks as a file or a pasted list: nothing a model writes skips them.
            let draft = try PlanImportNormalizer.draft(from: payload, defaults: defaults)
            // Cancelled while the answer was on its way: not shown, so not spent.
            guard !Task.isCancelled else {
                access.refund(.aiPlan)
                return
            }
            report(source, draft: draft)
            review(draft)
        } catch {
            access.refund(.aiPlan)
            guard !Task.isCancelled else { return }
            Analytics.track("plan_import_failed", ["source": .text(source), "reason": .text(analyticsReason(error))])
            failure = ImportFailure(error)
        }
    }

    private func readFile(_ result: Result<URL, any Error>, as request: FileRequest) async {
        guard case .success(let url) = result else { return }
        guard case .file(let data, _) = ImportInput.reading(fileAt: url) else {
            failure = ImportFailure(PlanImportError.unreadable)
            return
        }
        await read(request == .pdf || url.pathExtension.lowercased() == "pdf" ? .pdf(data) : .file(data))
    }

    private func readPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), data.count <= PlanLimits.importDocumentBytes else {
            failure = ImportFailure(PlanReadingError.noTextFound)
            return
        }
        await read(.image(data))
    }

    // MARK: Saving

    private func save(_ plan: MealPlan) {
        // Save answers once: a second tap while the sheet closes must not store the plan again.
        guard !didSave else { return }
        // Not stored: the store says why, and the review stays so nothing read is lost.
        guard store.attempt({ try store.createPlan(plan, activate: true) }) != nil else { return }
        didSave = true
        Analytics.track("plan_saved", ["source": .text(lastSource)])
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

/// Why an import stopped, as one of a fixed set of words. An error's own description can quote the
/// text it failed on, so it is never what gets sent.
private func analyticsReason(_ error: any Error) -> String {
    switch error {
    case let error as PlanImportError: String(describing: error)
    case let error as PlanAssistantError: String(describing: error)
    case is PlanReadingError: "noTextFound"
    default: "other"
    }
}

extension PlanSource {
    /// The way in, by name. The content never goes with it.
    var analyticsName: String {
        switch self {
        case .text: "paste"
        case .file: "file"
        case .image: "photo"
        case .pdf: "pdf"
        }
    }
}

/// A request held back until the person agrees to its text being sent.
private struct AssistantConsent: Identifiable {
    let id = UUID()
    let request: @MainActor () async -> Void
}

enum ImportRoute: Hashable {
    case paste
    case assistantOrganize
    case assistantCreate
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
        case PlanAssistantError.offline:
            message = String(localized: "import.assistant.error.offline", bundle: .module)
        case PlanAssistantError.tooLong:
            message = String(localized: "import.assistant.error.tooLong", bundle: .module)
        case PlanAssistantError.noPlan:
            message = String(localized: "import.assistant.error.noPlan", bundle: .module)
        case PlanAssistantError.busy:
            message = String(localized: "import.assistant.error.busy", bundle: .module)
        case PlanAssistantError.dailyLimit:
            message = String(localized: "import.assistant.error.dailyLimit", bundle: .module)
        case PlanAssistantError.unavailable:
            message = String(localized: "import.assistant.error.unavailable", bundle: .module)
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
    var title: LocalizedStringKey = "import.paste.title"
    var placeholder: LocalizedStringKey = "import.paste.placeholder"
    /// Characters the reader takes; past it Continue is off and a line says why.
    var characterLimit: Int = PlanLimits.importTextLength
    let onContinue: (String) -> Void
    @State private var text = ""
    @State private var nothingToPaste = false
    @FocusState private var isFocused: Bool

    private var isTooLong: Bool { text.count > characterLimit }

    /// Puts the clipboard in the box. After what is already there, if anything is: a plan copied
    /// in two pieces is still one plan, and a slip must not wipe what was typed.
    private func paste() {
        guard let pasted = UIPasteboard.general.string?.trimmedNonEmpty else {
            nothingToPaste = true
            return
        }
        text = text.trimmedNonEmpty == nil ? pasted : text + "\n" + pasted
    }

    var body: some View {
        TextEditor(text: $text)
            .focused($isFocused)
            .font(.body)
            .padding(.horizontal, AppSpacing.medium)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder, bundle: .module)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, AppSpacing.large)
                        .padding(.vertical, AppSpacing.xSmall)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .navigationTitle(Text(title, bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            // In the screen, above the keyboard: a bar at the bottom edge sits under the keyboard,
            // which is up for most of the time this screen is.
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
                    if isTooLong {
                        Text(String(localized: "import.paste.tooLong", defaultValue: "This is \(text.count) characters; up to \(characterLimit) can be read.", bundle: .module))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if nothingToPaste {
                        Text("import.paste.nothing", bundle: .module)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(action: paste) {
                            Label {
                                Text("import.paste.paste", bundle: .module)
                            } icon: {
                                Image(systemName: "doc.on.clipboard")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.brandAccent)
                        Spacer()
                        if !text.isEmpty {
                            Button(role: .destructive) {
                                text = ""
                            } label: {
                                Text("import.paste.clear", bundle: .module)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppSpacing.screenMargin)
                .padding(.vertical, AppSpacing.xSmall)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        isFocused = false
                        onContinue(text)
                    } label: {
                        Text("import.paste.continue", bundle: .module)
                    }
                    .disabled(text.trimmedNonEmpty == nil || isTooLong)
                }
            }
            .onChange(of: text) { nothingToPaste = false }
    }
}
