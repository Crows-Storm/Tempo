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
    var askedAccessibility: Bool = false
    var askedNotifications: Bool = false

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

    enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakInterval
        case monitorInterval, confirmDeleteCard, notificationsEnabled, soundEnabled
        case suggestBoard, appearance, language, distractionRules, welcomed
        case askedAccessibility, askedNotifications
    }

    init(
        focusMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        longBreakInterval: Int = 4,
        monitorInterval: Double = 2,
        confirmDeleteCard: Bool = true,
        notificationsEnabled: Bool = true,
        soundEnabled: Bool = true,
        suggestBoard: Bool = true,
        appearance: AppearanceChoice = .system,
        language: LanguagePreference = .system,
        distractionRules: [DistractionRule] = DistractionRule.presets,
        welcomed: Bool = false,
        askedAccessibility: Bool = false,
        askedNotifications: Bool = false
    ) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.longBreakInterval = longBreakInterval
        self.monitorInterval = monitorInterval
        self.confirmDeleteCard = confirmDeleteCard
        self.notificationsEnabled = notificationsEnabled
        self.soundEnabled = soundEnabled
        self.suggestBoard = suggestBoard
        self.appearance = appearance
        self.language = language
        self.distractionRules = distractionRules
        self.welcomed = welcomed
        self.askedAccessibility = askedAccessibility
        self.askedNotifications = askedNotifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppSettings()
        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? fallback.focusMinutes
        shortBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? fallback.shortBreakMinutes
        longBreakMinutes = try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? fallback.longBreakMinutes
        longBreakInterval = try container.decodeIfPresent(Int.self, forKey: .longBreakInterval) ?? fallback.longBreakInterval
        monitorInterval = try container.decodeIfPresent(Double.self, forKey: .monitorInterval) ?? fallback.monitorInterval
        confirmDeleteCard = try container.decodeIfPresent(Bool.self, forKey: .confirmDeleteCard) ?? fallback.confirmDeleteCard
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? fallback.notificationsEnabled
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? fallback.soundEnabled
        suggestBoard = try container.decodeIfPresent(Bool.self, forKey: .suggestBoard) ?? fallback.suggestBoard
        appearance = try container.decodeIfPresent(AppearanceChoice.self, forKey: .appearance) ?? fallback.appearance
        language = try container.decodeIfPresent(LanguagePreference.self, forKey: .language) ?? fallback.language
        distractionRules = try container.decodeIfPresent([DistractionRule].self, forKey: .distractionRules) ?? fallback.distractionRules
        welcomed = try container.decodeIfPresent(Bool.self, forKey: .welcomed) ?? fallback.welcomed
        askedAccessibility = try container.decodeIfPresent(Bool.self, forKey: .askedAccessibility) ?? false
        askedNotifications = try container.decodeIfPresent(Bool.self, forKey: .askedNotifications) ?? false
    }
}
