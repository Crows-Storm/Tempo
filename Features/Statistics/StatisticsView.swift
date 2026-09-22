import Charts
import SwiftUI

struct StatisticsView: View {
    var model: AppModel
    @State private var range: StatsRange = .week
    @State private var snapshot = StatisticsSnapshot.empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                Picker("Range", selection: $range) {
                    Text("Day").tag(StatsRange.day)
                    Text("Week").tag(StatsRange.week)
                    Text("Month").tag(StatsRange.month)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                headline
                chart
                AppHoursDonut(apps: snapshot.apps)
                TitleBars(titles: snapshot.titles)
                metrics
            }
            .padding(TempoSpacing.lg)
            .frame(maxWidth: 860, alignment: .leading)
        }
        .navigationTitle("Statistics")
        .task(id: taskKey) { reload() }
        .onChange(of: range) { _, _ in reload() }
    }

    private var taskKey: String { "\(model.revision)-\(range.rawValue)" }

    private func reload() {
        snapshot = Analytics.make(
            sessions: model.facts(),
            cards: model.cardFacts(),
            range: range,
            now: .now,
            calendar: .current
        )
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rangeTitle)
                .font(.caption)
                .foregroundStyle(TempoColor.secondary)
            Text(TempoFormat.minutesValue(TimeInterval(snapshot.points.reduce(0) { $0 + $1.minutes } * 60)))
                .font(.largeTitle.weight(.semibold))
                .monospacedDigit()
            Text("\(snapshot.pomodoros) pomodoros")
                .font(.callout)
                .foregroundStyle(TempoColor.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var rangeTitle: LocalizedStringKey {
        switch range {
        case .day: "Focus time today"
        case .week: "Focus time this week"
        case .month: "Focus time this month"
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("Trend")
                .font(.headline)
            if snapshot.points.allSatisfy({ $0.minutes == 0 }) {
                Text("No focus yet")
                    .foregroundStyle(TempoColor.secondary)
            } else {
                Chart(snapshot.points) { point in
                    BarMark(
                        x: .value("When", point.day, unit: unit),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(TempoColor.focus)
                    .cornerRadius(3)
                    .accessibilityLabel(Text(axisLabel(point.day)))
                    .accessibilityValue(Text("\(point.minutes)"))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: range == .month ? 8 : 6))
                }
                .chartYAxisLabel("Minutes")
                .frame(height: 200)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Focus time"))
            }
        }
    }

    private var unit: Calendar.Component {
        switch range {
        case .day: .hour
        case .week, .month: .day
        }
    }

    private func axisLabel(_ day: Date) -> String {
        switch range {
        case .day:
            day.formatted(date: .omitted, time: .shortened)
        case .week, .month:
            day.formatted(date: .abbreviated, time: .omitted)
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Summary")
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: TempoSpacing.xl, verticalSpacing: TempoSpacing.xs) {
                metric("Pomodoros", "\(snapshot.pomodoros)")
                metric("Completed tasks", "\(snapshot.completedCards)")
                metric("Streak", "\(snapshot.streak)")
                metric("Average session", snapshot.averageMinutes.map { "\($0) min" } ?? "—")
                metric("Completion", snapshot.completion?.formatted(.percent.precision(.fractionLength(0))) ?? "—")
                GridRow {
                    Text("Efficiency")
                    HStack(spacing: TempoSpacing.xs) {
                        Text(snapshot.efficiency?.formatted(.percent.precision(.fractionLength(0))) ?? "—")
                            .monospacedDigit()
                        Image(systemName: "info.circle")
                            .foregroundStyle(TempoColor.secondary)
                            .help("Efficiency is the share of samples that did not match your distraction list.")
                            .accessibilityLabel(Text("Efficiency is the share of samples that did not match your distraction list."))
                    }
                }
            }
            .font(.body)
        }
    }

    private func metric(_ title: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(title)
            Text(value).monospacedDigit()
        }
    }
}
