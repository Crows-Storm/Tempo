import SwiftUI

struct EmptyState: View {
    var systemImage: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(TempoColor.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3)
            Text(message)
                .font(.body)
                .foregroundStyle(TempoColor.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(TempoColor.info)
                    .padding(.top, TempoSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(TempoSpacing.xl)
    }
}

struct TimerReadout: View {
    var seconds: TimeInterval
    var phase: FocusPhase
    var compact: Bool = false
    var immersed: Bool = false

    var body: some View {
        Text(TempoFormat.clock(seconds))
            .font(immersed ? TempoFont.timerImmersed : (compact ? TempoFont.timerCompact : TempoFont.timer))
            .fontWeight(.light)
            .monospacedDigit()
            .foregroundStyle(TempoColor.label)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(PhaseCopy.title(phase)))
            .accessibilityValue(Text(TempoFormat.spoken(seconds)))
    }
}

struct FocusRing: View {
    var progress: Double
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(TempoColor.separator.opacity(0.45), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(TempoMotion.change(reduceMotion: reduceMotion), value: progress)
        }
        .accessibilityHidden(true)
    }
}

struct PhaseCopy {
    static func title(_ phase: FocusPhase) -> LocalizedStringKey {
        switch phase {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    static func spokenTitle(_ phase: FocusPhase) -> String {
        switch phase {
        case .focus: String(localized: "Focus")
        case .shortBreak: String(localized: "Short Break")
        case .longBreak: String(localized: "Long Break")
        }
    }
}

struct CardEffortMeter: View {
    var actualHours: Double
    var estimatedHours: Double
    var donePomodoros: Int
    var plannedPomodoros: Int

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            ProgressView(value: CardEffort.fraction(actualHours: actualHours, estimatedHours: estimatedHours))
                .progressViewStyle(.linear)
                .tint(over ? TempoColor.focus : TempoColor.info)
            HStack(spacing: TempoSpacing.xs) {
                Image(systemName: "timer")
                    .foregroundStyle(TempoColor.focus)
                    .accessibilityHidden(true)
                Text("\(donePomodoros)/\(plannedPomodoros)")
                    .foregroundStyle(TempoColor.label)
                    .monospacedDigit()
                if plannedPomodoros <= 8 {
                    pomodoroPips
                }
                Spacer(minLength: TempoSpacing.xs)
                Text("\(TempoFormat.minutesValue(actualHours * 3600)) / \(TempoFormat.minutesValue(estimatedHours * 3600))")
                    .foregroundStyle(TempoColor.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Pomodoros"))
        .accessibilityValue(
            Text("\(donePomodoros) / \(plannedPomodoros), \(TempoFormat.spoken(actualHours * 3600))")
        )
    }

    private var over: Bool {
        CardEffort.isOverEstimate(actualHours: actualHours, estimatedHours: estimatedHours)
    }

    private var pomodoroPips: some View {
        HStack(spacing: 3) {
            ForEach(0..<plannedPomodoros, id: \.self) { index in
                Circle()
                    .fill(index < donePomodoros ? TempoColor.focus : TempoColor.separator.opacity(0.45))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

struct TempoSearchable: ViewModifier {
    @Binding var text: String
    var nonce: Int
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .searchable(text: $text, prompt: Text("Search"))
            .searchFocused($focused)
            .onChange(of: nonce) { _, _ in
                focused = true
            }
    }
}

extension View {
    func tempoSearchable(text: Binding<String>, nonce: Int) -> some View {
        modifier(TempoSearchable(text: text, nonce: nonce))
    }
}

struct DesignSystemCatalog: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            TimerReadout(seconds: 25 * 60, phase: .focus)
            FocusRing(progress: 0.4, tint: TempoColor.focus)
                .frame(width: 120, height: 120)
            HStack(spacing: TempoSpacing.md) {
                swatch(TempoColor.focus, "Focus")
                swatch(TempoColor.breakTint, "Break")
                swatch(TempoColor.info, "Info")
            }
        }
        .padding(TempoSpacing.lg)
        .frame(width: 480)
    }

    private func swatch(_ color: Color, _ name: LocalizedStringKey) -> some View {
        VStack {
            RoundedRectangle(cornerRadius: TempoRadius.small)
                .fill(color)
                .frame(width: 48, height: 48)
            Text(name)
                .font(.caption)
        }
    }
}

#Preview("Design System") {
    DesignSystemCatalog()
}
