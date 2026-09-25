import Foundation

enum SystemChrome: Sendable {
    static func isIgnored(appName: String, bundleID: String = "") -> Bool {
        let bundle = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bundle.isEmpty, bundles.contains(bundle) { return true }
        return names.contains(appName.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static let bundles: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.UserNotificationCenter",
        "com.apple.WindowManager",
        "com.apple.wallpaper.agent",
        "com.apple.screencaptureui",
        "com.apple.SecurityAgent"
    ]

    private static let names: Set<String> = [
        "loginwindow",
        "ScreenSaverEngine",
        "Dock",
        "Control Centre",
        "Control Center",
        "Notification Centre",
        "Notification Center",
        "Window Manager",
        "Spotlight"
    ]
}
