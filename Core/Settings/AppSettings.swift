import Foundation

enum LanguagePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case en
    case zhHans = "zh-Hans"
    case ja

    var id: String { rawValue }

    var resolvedLocale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .en: Locale(identifier: "en")
        case .zhHans: Locale(identifier: "zh-Hans")
        case .ja: Locale(identifier: "ja")
        }
    }

    func apply() {
        switch self {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .en:
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        case .zhHans:
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        case .ja:
            UserDefaults.standard.set(["ja"], forKey: "AppleLanguages")
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var focusMinutes: Int = 25
    var shortBreakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    var longBreakInterval: Int = 4
    var monitorInterval: Double = 2
    var confirmDeleteCard: Bool = true
    var notificationsEnabled: Bool = true
    var soundEnabled: Bool = true
    var suggestBoard: Bool = true
    var appearance: AppearanceChoice = .system
    var language: LanguagePreference = .system
    var distractionRules: [DistractionRule] = DistractionRule.presets
    var welcomed: Bool = false

    static let storageKey = "tempo.settings"

    var durations: FocusDurations {
        FocusDurations(
            focus: TimeInterval(max(1, focusMinutes) * 60),
            shortBreak: TimeInterval(max(1, shortBreakMinutes) * 60),
            longBreak: TimeInterval(max(1, longBreakMinutes) * 60),
            longBreakEvery: max(1, longBreakInterval),
            rottenBefore: 10 * 60
        )
    }

    static func load(defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        var settings = decoded
        let rules = DistractionRule.resolved(settings.distractionRules)
        if rules != settings.distractionRules {
            settings.distractionRules = rules
            settings.save(defaults: defaults)
        }
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
