import AppKit
import UserNotifications

enum SessionNotifier {
    @MainActor
    static func deliver(
        enabled: Bool,
        title: String,
        body: String,
        playSound: Bool,
        didAsk: inout Bool
    ) async -> Bool {
        guard enabled else { return false }
        let allowed = await requestIfNeeded(didAsk: &didAsk)
        guard allowed else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playSound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        return true
    }

    @MainActor
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @MainActor
    static func isGranted() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    @MainActor
    static func requestIfNeeded(didAsk: inout Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            guard PermissionAsk.shouldShowSystemPrompt(didAsk: didAsk, isGranted: false) else {
                return false
            }
            didAsk = true
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            didAsk = true
            return false
        }
    }

    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }
}
