import Foundation

enum PermissionSettingsAction: Equatable, Sendable {
    case none
    case askSystem
    case openSystemSettings
}

enum PermissionAsk: Equatable, Sendable {
    static func shouldShowSystemPrompt(didAsk: Bool, isGranted: Bool) -> Bool {
        !isGranted && !didAsk
    }

    static func settingsAction(didAsk: Bool, isGranted: Bool) -> PermissionSettingsAction {
        if isGranted { return .none }
        return didAsk ? .openSystemSettings : .askSystem
    }
}
