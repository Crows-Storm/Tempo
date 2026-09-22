import UserNotifications

enum SessionNotifier {
    @MainActor
    static func deliver(enabled: Bool, title: String, body: String, playSound: Bool) async -> Bool {
        guard enabled else { return false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let allowed: Bool
        switch settings.authorizationStatus {
        case .notDetermined:
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            allowed = true
        default:
            allowed = false
        }
        guard allowed else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if playSound { content.sound = .default }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
        return true
    }
}
