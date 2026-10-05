import Foundation

/// The language the app is showing. iOS picks it — from the person's preferred languages, or the
/// one chosen for this app alone in the Settings app — out of the localizations the app bundle
/// ships, so a newly shipped language needs no code here.
public enum AppLanguage {
    /// The code of the language in use: "tr", "pt-BR", "zh-Hans".
    public static func currentCode(bundle: Bundle = .main) -> String {
        bundle.preferredLocalizations.first { $0 != "Base" } ?? bundle.developmentLocalization ?? "en"
    }

    /// The language in use, named in itself: "Türkçe", "English", "Español", "日本語".
    public static func currentName(bundle: Bundle = .main) -> String {
        name(of: currentCode(bundle: bundle))
    }

    /// How many languages the app ships, the source included.
    public static func availableCount(bundle: Bundle = .main) -> Int {
        Set(bundle.localizations.filter { $0 != "Base" }).count
    }

    /// A language named in itself, capitalized the way a list shows it: "Português (Brasil)".
    public static func name(of code: String) -> String {
        let language = Locale(identifier: code)
        guard let name = language.localizedString(forIdentifier: code), let first = name.first else { return code }
        return String(first).uppercased(with: language) + name.dropFirst()
    }

    /// Whether the language in use is written right to left.
    public static func isRightToLeft(bundle: Bundle = .main) -> Bool {
        Locale.Language(identifier: currentCode(bundle: bundle)).characterDirection == .rightToLeft
    }
}
