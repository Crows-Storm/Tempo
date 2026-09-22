import AppKit
import SwiftUI

enum TempoColor {
    static var focus: Color { Color(nsColor: .systemRed) }
    static var breakTint: Color { Color(nsColor: .systemYellow) }
    static var info: Color { Color(nsColor: .systemBlue) }
    static var label: Color { Color(nsColor: .labelColor) }
    static var secondary: Color { Color(nsColor: .secondaryLabelColor) }
    static var tertiary: Color { Color(nsColor: .tertiaryLabelColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
    static var window: Color { Color(nsColor: .windowBackgroundColor) }
    static var control: Color { Color(nsColor: .controlBackgroundColor) }

    static func heatmap(_ level: Int) -> Color {
        switch level {
        case 0: separator.opacity(0.35)
        case 1: focus.opacity(0.28)
        case 2: focus.opacity(0.48)
        case 3: focus.opacity(0.7)
        default: focus
        }
    }

    static func app(_ name: String) -> Color {
        let palette: [NSColor] = [
            .systemBlue, .systemPurple, .systemTeal, .systemOrange,
            .systemIndigo, .systemPink, .systemCyan, .systemMint,
            .systemBrown, .systemGreen
        ]
        let index = abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palette.count
        return Color(nsColor: palette[index])
    }

    static func phase(_ phase: FocusPhase) -> Color {
        switch phase {
        case .focus:
            focus
        case .shortBreak, .longBreak:
            breakTint
        }
    }
}

enum AppearanceChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor
    func apply() {
        let application = NSApplication.shared
        switch self {
        case .system:
            application.appearance = nil
        case .light:
            application.appearance = NSAppearance(named: .aqua)
        case .dark:
            application.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum TempoSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum TempoRadius {
    static let small: CGFloat = 6
    static let control: CGFloat = 8
    static let column: CGFloat = 10
}

enum TempoMotion {
    static let quick: TimeInterval = 0.18

    static func change(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: quick)
    }

    static func session(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.56, extraBounce: 0.04)
    }

    static func sessionTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985)).combined(with: .offset(x: 18)),
            removal: .opacity.combined(with: .scale(scale: 1.008)).combined(with: .offset(x: -14))
        )
    }
}

enum TempoFont {
    static let timer = Font.system(size: 52, weight: .light, design: .rounded)
    static let timerImmersed = Font.system(size: 64, weight: .light, design: .rounded)
    static let timerCompact = Font.system(size: 20, weight: .light, design: .rounded)
    static let metric = Font.system(size: 28, weight: .regular, design: .rounded)
}

enum TempoFormat {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func spoken(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: max(0, seconds)) ?? clock(seconds)
    }

    static func minutesValue(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        if seconds < 60 {
            formatter.allowedUnits = [.second]
        } else {
            formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        }
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, seconds)) ?? "0"
    }
}

struct TempoChrome: ViewModifier {
    var model: AppModel

    func body(content: Content) -> some View {
        content
            .environment(\.locale, model.settings.language.resolvedLocale)
            .onAppear { model.settings.appearance.apply() }
            .onChange(of: model.settings.appearance) { _, appearance in
                appearance.apply()
            }
    }
}

extension View {
    func tempoChrome(_ model: AppModel) -> some View {
        modifier(TempoChrome(model: model))
    }
}
