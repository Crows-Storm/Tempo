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

    static func didAskForCurrentBinary(didAsk: Bool, storedPath: String, currentPath: String) -> Bool {
        didAsk && !currentPath.isEmpty && storedPath == currentPath
    }

    static func settingsAction(didAsk: Bool, isGranted: Bool) -> PermissionSettingsAction {
        if isGranted { return .none }
        return didAsk ? .openSystemSettings : .askSystem
    }
}
