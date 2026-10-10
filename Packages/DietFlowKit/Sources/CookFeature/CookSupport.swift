import AVFoundation
import Foundation
import Observation
import SwiftUI
import UserNotifications
import DesignSystem
import Domain

// MARK: Timers

/// The timers of one cooking session, one per step that waits. Each counts down to an end date, so
/// what the screen shows stays right however long the phone sleeps or the app is away; a local
/// notification says when it ends, but only when the person already allows notifications.
@Observable
final class CookTimers {
    struct Running: Equatable {
        let start: Date
        let end: Date

        /// What `Text(timerInterval:)` counts down; never a reversed range, which would trap.
        var interval: ClosedRange<Date> { min(start, end)...end }
    }

    /// Timers started, by step number, until they are stopped; a finished one stays until cleared.
    private(set) var running: [Int: Running] = [:]
    /// Steps whose timer has run out.
    private(set) var finished: Set<Int> = []
    /// Goes up each time a timer runs out, for the haptic.
    private(set) var finishedCount = 0

    @ObservationIgnored private var waits: [Int: Task<Void, Never>] = [:]

    /// Starts `step`'s timer from now, replacing one already running.
    func start(step: Int, minutes: Int, alertTitle: String, alertBody: String) {
        stop(step: step)
        let seconds = max(1, minutes) * 60
        let now = Date.now
        running[step] = Running(start: now, end: now.addingTimeInterval(TimeInterval(seconds)))
        waits[step] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish(step: step)
        }
        let id = Self.alertID(step)
        Task {
            await CookAlerts.schedule(id: id, title: alertTitle, body: alertBody, after: TimeInterval(seconds))
        }
    }

    /// Stops or clears `step`'s timer, and its notification with it.
    func stop(step: Int) {
        waits[step]?.cancel()
        waits[step] = nil
        running[step] = nil
        finished.remove(step)
        CookAlerts.cancel([Self.alertID(step)])
    }

    /// Every timer, when cooking ends or the recipe changes under them.
    func stopAll() {
        let steps = Set(running.keys).union(waits.keys)
        for wait in waits.values { wait.cancel() }
        waits = [:]
        running = [:]
        finished = []
        CookAlerts.cancel(steps.map(Self.alertID))
    }

    private func finish(step: Int) {
        waits[step] = nil
        guard running[step] != nil else { return }
        finished.insert(step)
        finishedCount += 1
    }

    private static func alertID(_ step: Int) -> String {
        "cook.timer.\(step)"
    }
}

/// The notification at the end of a step's timer. Cook mode never asks for permission: a person who
/// turned reminders off has said what they want, and the timer on screen still runs.
nonisolated enum CookAlerts {
    @concurrent
    static func schedule(id: String, title: String, body: String, after seconds: TimeInterval) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "cook"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch {
            // The timer on screen still runs; only the notification is missing.
            return
        }
    }

    static func cancel(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: Reading aloud

/// Reads steps aloud in the app's language, so hands busy with food need not touch the phone. Other
/// audio is ducked while it speaks, and it is heard with the ring switch on silent, as a kitchen
/// timer would be.
final class CookVoice {
    private let synthesizer = AVSpeechSynthesizer()
    private var holdsAudio = false

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if !holdsAudio {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try? session.setActive(true)
            holdsAudio = true
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: AppLanguage.currentCode())
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if holdsAudio {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            holdsAudio = false
        }
    }

    /// A voice for the app's language, in the person's own region when there is one ("es-MX"
    /// rather than "es-ES"), and the better of the installed voices otherwise.
    private static func voice(for code: String) -> AVSpeechSynthesisVoice? {
        let language = Locale(identifier: code).language.languageCode?.identifier ?? code
        if let region = Locale.current.region?.identifier, let regional = AVSpeechSynthesisVoice(language: "\(language)-\(region)") {
            return regional
        }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language || $0.language.hasPrefix(language + "-") }
        return voices.first { $0.quality != .default } ?? voices.first ?? AVSpeechSynthesisVoice(language: language)
    }
}

// MARK: Step kinds

extension Recipe.StepKind {
    /// What the step's tile shows. Symbols that have been in SF Symbols for years.
    var symbolName: String {
        switch self {
        case .prep: "list.bullet.clipboard"
        case .chop: "scissors"
        case .mix: "arrow.triangle.2.circlepath"
        case .heat: "flame"
        case .boil: "drop"
        case .fry: "frying.pan"
        case .bake: "oven"
        case .grill: "square.grid.3x3.fill"
        case .blend: "wind"
        case .rest: "hourglass"
        case .cool: "snowflake"
        case .season: "leaf"
        case .plate: "fork.knife"
        case .other: "circle.grid.2x2"
        }
    }

    /// The tile's colour: warm for heat, cool for cold and waiting. The symbol and the name carry
    /// the meaning; the colour only helps the eye.
    var tint: Color {
        switch self {
        case .prep: .teal
        case .chop: .green
        case .mix: .blue
        case .heat, .fry: .orange
        case .boil: .cyan
        case .bake, .grill: .red
        case .blend: .purple
        case .rest: .indigo
        case .cool: .cyan
        case .season: .mint
        case .plate: AppColors.brandAccent
        case .other: .gray
        }
    }

    /// The step's kind in a word, above its text; nil for a step of no particular kind.
    var name: String? {
        switch self {
        case .prep: String(localized: "cook.kind.prep", bundle: .module)
        case .chop: String(localized: "cook.kind.chop", bundle: .module)
        case .mix: String(localized: "cook.kind.mix", bundle: .module)
        case .heat: String(localized: "cook.kind.heat", bundle: .module)
        case .boil: String(localized: "cook.kind.boil", bundle: .module)
        case .fry: String(localized: "cook.kind.fry", bundle: .module)
        case .bake: String(localized: "cook.kind.bake", bundle: .module)
        case .grill: String(localized: "cook.kind.grill", bundle: .module)
        case .blend: String(localized: "cook.kind.blend", bundle: .module)
        case .rest: String(localized: "cook.kind.rest", bundle: .module)
        case .cool: String(localized: "cook.kind.cool", bundle: .module)
        case .season: String(localized: "cook.kind.season", bundle: .module)
        case .plate: String(localized: "cook.kind.plate", bundle: .module)
        case .other: nil
        }
    }
}

extension Recipe.Difficulty {
    var name: String {
        switch self {
        case .easy: String(localized: "cook.difficulty.easy", bundle: .module)
        case .medium: String(localized: "cook.difficulty.medium", bundle: .module)
        case .hard: String(localized: "cook.difficulty.hard", bundle: .module)
        }
    }
}

// MARK: Words

enum CookWords {
    /// What went wrong asking for a recipe, in words that say what to do next.
    static func message(for error: AssistantError) -> String {
        switch error {
        case .offline: String(localized: "cook.error.offline", bundle: .module)
        case .busy: String(localized: "cook.error.busy", bundle: .module)
        case .dailyLimit: String(localized: "cook.error.dailyLimit", bundle: .module)
        case .tooLong: String(localized: "cook.error.tooLong", bundle: .module)
        case .noPlan: String(localized: "cook.error.noPlan", bundle: .module)
        case .unavailable: String(localized: "cook.error.unavailable", bundle: .module)
        }
    }

    static func symbol(for error: AssistantError) -> String {
        error == .offline ? "wifi.slash" : "exclamationmark.triangle"
    }

    /// What the screen says while the recipe is written: what the assistant is actually asked to do,
    /// one line at a time.
    static func thinkingLines(avoids: Bool) -> [String] {
        var lines = [
            String(localized: "cook.loading.reading", bundle: .module),
            String(localized: "cook.loading.steps", bundle: .module),
            String(localized: "cook.loading.swaps", bundle: .module),
        ]
        if avoids {
            lines.append(String(localized: "cook.loading.avoid", bundle: .module))
        }
        return lines
    }
}
