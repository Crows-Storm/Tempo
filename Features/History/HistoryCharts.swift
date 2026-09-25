import Charts
import SwiftUI

struct AppHoursDonut: View {
    var apps: [AppSlice]
    var title: LocalizedStringKey = "Apps"

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(title)
                .font(.headline)
            if apps.isEmpty {
                Text("No focus yet")
                    .foregroundStyle(TempoColor.secondary)
            } else {
                HStack(alignment: .center, spacing: TempoSpacing.lg) {
                    Chart(apps) { app in
                        SectorMark(
                            angle: .value("Time", app.seconds),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.4
                        )
                        .foregroundStyle(TempoColor.app(app.name))
                        .cornerRadius(3)
                        .accessibilityLabel(Text(app.name))
                        .accessibilityValue(Text("\(percent(app)), \(TempoFormat.spoken(app.seconds))"))
                    }
                    .chartBackground { _ in
                        VStack(spacing: 2) {
                            Text(TempoFormat.minutesValue(total))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                            Text("Total")
                                .font(.caption)
                                .foregroundStyle(TempoColor.secondary)
                        }
                        .accessibilityHidden(true)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 180, height: 180)
                    VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                        ForEach(apps) { app in
                            HStack(spacing: TempoSpacing.xs) {
                                Circle()
                                    .fill(TempoColor.app(app.name))
                                    .frame(width: 8, height: 8)
                                Text(app.name)
                                    .lineLimit(1)
                                Spacer(minLength: TempoSpacing.xs)
                                Text(TempoFormat.minutesValue(app.seconds))
                                    .foregroundStyle(TempoColor.secondary)
                                    .monospacedDigit()
                            }
                            .font(.callout)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(title))
            }
        }
    }

    private var total: TimeInterval {
        apps.reduce(0) { $0 + $1.seconds }
    }

    private func percent(_ app: AppSlice) -> String {
        guard total > 0 else { return "0%" }
        return (app.seconds / total).formatted(.percent.precision(.fractionLength(0)))
    }
}

struct PomodoroLaneChart: View {
    var intervals: [FocusInterval]
    var length: TimeInterval
    var height: CGFloat = 36
    var showsAxis: Bool = false
    var accessibilityTitle: LocalizedStringKey = "This session"

    var body: some View {
        let domain = max(1, length / 60)
        Chart(intervals) { item in
            BarMark(
                xStart: .value("Start", item.start / 60),
                xEnd: .value("End", item.end / 60),
                y: .value("Lane", "Apps")
            )
            .foregroundStyle(TempoColor.app(item.app))
            .opacity(item.distracted ? 0.45 : 1)
            .cornerRadius(3)
            .accessibilityLabel(Text(item.app))
            .accessibilityValue(Text(TempoFormat.spoken(item.duration)))
        }
        .chartXScale(domain: 0...domain)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .modifier(LaneAxis(showsAxis: showsAxis))
        .chartPlotStyle { plot in
            plot.background {
                RoundedRectangle(cornerRadius: TempoRadius.small, style: .continuous)
                    .fill(.quaternary.opacity(0.28))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityTitle))
    }
}

private struct LaneAxis: ViewModifier {
    var showsAxis: Bool

    func body(content: Content) -> some View {
        if showsAxis {
            content.chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text("\(Int(minutes.rounded()))")
                        }
                    }
                }
            }
        } else {
            content.chartXAxis(.hidden)
        }
    }
}

struct AttentionStrip: View {
    var focused: TimeInterval
    var distracted: TimeInterval

    var body: some View {
        let total = focused + distracted
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("Attention")
                .font(.headline)
            if total <= 0 {
                Text("No window activity for this session.")
                    .foregroundStyle(TempoColor.secondary)
            } else {
                Chart {
                    BarMark(x: .value("Focused", focused / 60), y: .value("Lane", "Attention"))
                        .foregroundStyle(TempoColor.focus)
                        .accessibilityLabel(Text("Focused"))
                        .accessibilityValue(Text(TempoFormat.spoken(focused)))
                    BarMark(x: .value("Distracted", distracted / 60), y: .value("Lane", "Attention"))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .accessibilityLabel(Text("Distracted"))
                        .accessibilityValue(Text(TempoFormat.spoken(distracted)))
                }
                .chartXScale(domain: 0...(total / 60))
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .chartPlotStyle { plot in
                    plot.background {
                        Capsule().fill(.quaternary.opacity(0.28))
                    }
                }
                .frame(height: 18)
                HStack {
                    Label("Focused", systemImage: "circle.fill")
                        .foregroundStyle(TempoColor.focus)
                    Label("Distracted", systemImage: "circle.fill")
                        .foregroundStyle(TempoColor.secondary)
                    Spacer()
                    Text((focused / total).formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(TempoColor.secondary)
                }
                .font(.caption)
                .labelStyle(.titleAndIcon)
                .symbolRenderingMode(.monochrome)
                .imageScale(.small)
            }
        }
    }
}

struct TitleBars: View {
    var titles: [TitleSlice]

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Titles")
                .font(.headline)
            if titles.isEmpty {
                Text("No window titles in this range.")
                    .foregroundStyle(TempoColor.secondary)
            } else {
                Chart(Array(titles.prefix(8))) { title in
                    BarMark(
                        x: .value("Minutes", title.seconds / 60),
                        y: .value("Title", title.title)
                    )
                    .foregroundStyle(TempoColor.info)
                    .cornerRadius(3)
                    .accessibilityLabel(Text(title.title))
                    .accessibilityValue(Text(TempoFormat.spoken(title.seconds)))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let title = value.as(String.self) {
                                Text(title)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .chartXAxisLabel("Minutes", alignment: .trailing)
                .frame(height: CGFloat(min(8, titles.count)) * 28 + 28)
                .accessibilityElement(children: .contain)
            }
        }
    }
}

struct MonthCalendar: View {
    var sessions: [SessionFact]
    var selected: Date
    var select: (Date) -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Button {
                    shift(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Previous Month"))
                Text(selected.formatted(.dateTime.month(.wide).year()))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 140)
                Button {
                    shift(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!canGoForward)
                .accessibilityLabel(Text("Next Month"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 28), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption)
                        .foregroundStyle(TempoColor.secondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(cells) { cell in
                    dayButton(cell)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { symbols[($0 + first) % symbols.count] }
    }

    private var canGoForward: Bool {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selected)) ?? selected
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? selected
        return next <= Date()
    }

    private var cells: [CalendarCell] {
        let month = calendar.date(from: calendar.dateComponents([.year, .month], from: selected)) ?? selected
        let weekday = calendar.component(.weekday, from: month)
        let pad = (weekday - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let totals = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.start) }
            .mapValues { list in (minutes: Int(list.reduce(0) { $0 + $1.seconds } / 60), count: list.count) }
        var items: [CalendarCell] = (0..<pad).map {
            CalendarCell(id: "pad-\($0)", day: nil, minutes: 0, sessions: 0)
        }
        for day in 1...days {
            let date = calendar.date(byAdding: .day, value: day - 1, to: month) ?? month
            let start = calendar.startOfDay(for: date)
            let value = totals[start] ?? (0, 0)
            items.append(CalendarCell(id: start.timeIntervalSince1970.description, day: start, minutes: value.minutes, sessions: value.count))
        }
        return items
    }

    private func dayButton(_ cell: CalendarCell) -> some View {
        Group {
            if let day = cell.day {
                let isSelected = calendar.isDate(day, inSameDayAs: selected)
                let future = day > calendar.startOfDay(for: Date())
                Button {
                    select(day)
                } label: {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.body)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(fill(minutes: cell.minutes, selected: isSelected))
                        }
                        .foregroundStyle(isSelected ? Color.white : (cell.minutes > 0 ? TempoColor.label : TempoColor.secondary))
                        .overlay {
                            if contrast == .increased {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(TempoColor.secondary, lineWidth: 0.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(future)
                .help(help(cell, day: day))
                .accessibilityLabel(Text(day.formatted(date: .abbreviated, time: .omitted)))
                .accessibilityValue(Text("\(cell.minutes) \(cell.sessions)"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                Color.clear.frame(minHeight: 28)
            }
        }
    }

    private func fill(minutes: Int, selected: Bool) -> Color {
        if selected { return TempoColor.focus }
        switch minutes {
        case 0: return Color.primary.opacity(0.06)
        case 1..<25: return TempoColor.focus.opacity(0.22)
        case 25..<50: return TempoColor.focus.opacity(0.4)
        case 50..<100: return TempoColor.focus.opacity(0.62)
        default: return TempoColor.focus.opacity(0.84)
        }
    }

    private func help(_ cell: CalendarCell, day: Date) -> String {
        "\(day.formatted(date: .abbreviated, time: .omitted)) · \(cell.minutes) · \(cell.sessions)"
    }

    private func shift(_ delta: Int) {
        guard let month = calendar.date(from: calendar.dateComponents([.year, .month], from: selected)),
              let next = calendar.date(byAdding: .month, value: delta, to: month) else { return }
        if delta > 0, next > Date() { return }
        select(next)
    }
}

private struct CalendarCell: Identifiable {
    var id: String
    var day: Date?
    var minutes: Int
    var sessions: Int
}
