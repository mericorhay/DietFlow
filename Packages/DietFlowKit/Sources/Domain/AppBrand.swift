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
