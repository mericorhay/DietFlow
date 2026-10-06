import Foundation

/// The app's name as the person sees it under its icon. Set once, in the build settings
/// (`APP_DISPLAY_NAME` in Config/Shared.xcconfig) and the Info.plist string catalog; the code only
/// ever reads it, so a new marketing name never means a code change.
public enum AppBrand {
    public static var displayName: String {
        let bundle = Bundle.main
        let name = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        return name?.trimmedNonEmpty ?? ""
    }
}

/// The app's own pages, published from `docs/` by GitHub Pages: what every screen that mentions
/// the terms, the privacy policy or help links to, and what App Store Connect is given.
public enum LegalLinks {
    public static let privacy = URL(string: "https://mericorhay.github.io/DietFlow/privacy")!
    public static let terms = URL(string: "https://mericorhay.github.io/DietFlow/terms")!
    public static let support = URL(string: "https://mericorhay.github.io/DietFlow/support")!
}

/// Whose AI the assistant's server passes the person's text to. The app names it wherever it
/// asks for that text, so this has to be the company the server (backend/assistant) really
/// calls: change the one, change the other, and docs/privacy.md and docs/terms.md with them.
public enum AssistantProvider {
    public static let name = "OpenAI"
}
