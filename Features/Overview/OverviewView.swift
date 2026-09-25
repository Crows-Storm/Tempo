import SwiftUI

struct OverviewView: View {
    @Bindable var model: AppModel
    @State private var snapshot = StatisticsSnapshot.empty
    @State private var todayIntervals: [FocusInterval] = []
    @State private var todayLength: TimeInterval = 0
    @State private var todaySankey = SankeyDiagram.empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                nowAndToday
                nextWork
                boards
                todayFocus
            }
            .padding(TempoSpacing.lg)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .navigationTitle("Overview")
        .tempoSearchable(text: $model.searchText, nonce: model.searchFocusNonce)
        .task(id: model.revision) { reload() }
        .task(id: todayLoadKey) { await loadTodayFocus() }
    }

    private func reload() {
        snapshot = Analytics.make(
            sessions: model.facts(),
            cards: model.cardFacts(),
            range: .day,
            now: .now,
            calendar: .current
        )
    }

    private var nowAndToday: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: TempoSpacing.md) {
                nowCard
                todayCard
            }
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                nowCard
                todayCard
            }
        }
    }

    private var nowCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(model.clock.runState == .idle ? "Ready" : PhaseCopy.title(model.clock.phase))
                .font(.headline)
                .foregroundStyle(TempoColor.secondary)
            if model.clock.runState == .idle {
                Text(Date.now, format: Date.FormatStyle(date: .complete, time: .omitted))
                    .font(.title2)
                    .foregroundStyle(TempoColor.label)
            } else {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    TimerReadout(
                        seconds: model.remaining(at: context.date),
                        phase: model.clock.phase,
                        compact: true
                    )
                    .onChange(of: context.date) { _, date in
                        model.reconcile(now: date)
                    }
                }
            }
            HStack(spacing: TempoSpacing.sm) {
                Button(primaryTitle) { primaryAction() }
                    .buttonStyle(.borderedProminent)
                    .tint(TempoColor.phase(model.clock.phase == .focus || model.clock.runState == .idle ? .focus : model.clock.phase))
                    .keyboardShortcut(.defaultAction)
                if model.clock.runState != .idle {
                    Button("Open Focus") { model.section = .focus }
                }
            }
            .controlSize(.regular)
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(cardBackground)
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Today")
                .font(.headline)
                .foregroundStyle(TempoColor.secondary)
            HStack(alignment: .top, spacing: TempoSpacing.xl) {
                metric(TempoFormat.minutesValue(TimeInterval(todayMinutes * 60)), "Focus time")
                metric("\(todayPomodoros)", "Pomodoros")
                if snapshot.streak > 0 {
                    metric("\(snapshot.streak)", "Streak")
                }
            }
            if !weekDays.isEmpty {
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text("This week")
                        .font(.caption)
                        .foregroundStyle(TempoColor.secondary)
                    HStack(spacing: 5) {
                        ForEach(weekDays) { day in
                            Button {
                                model.historyDay = day.day
                                model.section = .history
                            } label: {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(TempoColor.heatmap(day.level))
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .help(weekHelp(day))
                            .accessibilityLabel(Text(day.day.formatted(date: .abbreviated, time: .omitted)))
                            .accessibilityValue(Text("\(day.minutes)"))
                        }
                    }
                }
            }
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(cardBackground)
        .accessibilityLabel(Text("Today"))
    }

    private func metric(_ value: String, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(TempoFont.metric)
                .foregroundStyle(TempoColor.label)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(TempoColor.secondary)
        }
    }

    private var nextWork: some View {
        let items = model.upcomingWork()
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Next")
                .font(.headline)
            if items.isEmpty {
                Text("Nothing in progress")
                    .foregroundStyle(TempoColor.secondary)
                Button("Open Tasks") { model.section = .tasks }
                    .buttonStyle(.link)
            } else {
                ForEach(items) { item in
                    HStack(spacing: TempoSpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.body)
                            Text(item.boardName)
                                .font(.caption)
                                .foregroundStyle(TempoColor.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Focus") {
                            model.selectFocusCard(item.id)
                            model.start()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var boards: some View {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = model.boardOverviews().filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Boards")
                .font(.headline)
            LazyVGrid(columns: BoardGrid.columns, spacing: TempoSpacing.md) {
                ForEach(items) { board in
                    BoardCard(
                        board: board,
                        action: { open(board) },
                        pin: { model.togglePin(board.id) },
                        archive: { model.archiveBoard(board.id) },
                        unarchive: { model.unarchiveBoard(board.id) },
                        delete: { model.deleteBoard(board.id) }
                    )
                }
                NewBoardCard { model.showNewBoard = true }
            }
        }
    }

    private var todayFocus: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Today's focus")
                .font(.headline)
            if todaySessions.isEmpty {
                Text("What you focus on shows up here.")
                    .foregroundStyle(TempoColor.secondary)
            } else {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    PomodoroLaneChart(
                        intervals: todayIntervals,
                        length: max(1, todayLength),
                        height: 52,
                        showsAxis: true,
                        accessibilityTitle: "Today's focus"
                    )
                    todayLegend
                }
                SessionSankey(diagram: todaySankey)
            }
        }
    }

    private var todayLegend: some View {
        let apps = Dictionary(grouping: todayIntervals, by: \.app)
            .map { AppSlice(name: $0.key, seconds: $0.value.reduce(0) { $0 + $1.duration }) }
            .sorted { $0.seconds > $1.seconds }
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: TempoSpacing.md, alignment: .leading)],
            alignment: .leading,
            spacing: TempoSpacing.xs
        ) {
            ForEach(apps.prefix(6)) { app in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(TempoColor.app(app.name))
                        .frame(width: 10, height: 10)
                    Text(app.name)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(TempoColor.secondary)
            }
        }
    }

    private var todaySessions: [SessionFact] {
        model.facts()
            .filter { Calendar.current.isDateInToday($0.start) }
            .sorted { $0.start < $1.start }
    }

    private var todayLoadKey: String {
        todaySessions.map(\.id).joined(separator: ",") + "-\(model.revision)"
    }

    private func loadTodayFocus() async {
        let sessions = todaySessions
        let rules = model.settings.distractionRules
        let fallback = model.settings.monitorInterval
        var parts: [(session: SessionFact, intervals: [FocusInterval])] = []
        var samples: [ActivitySample] = []
        for session in sessions {
            let captured = (try? await model.activity.samples(sessionID: session.id)) ?? []
            samples.append(contentsOf: captured)
            parts.append((
                session,
                FocusLane.make(
                    samples: captured,
                    session: session,
                    rules: rules,
                    fallback: fallback
                )
            ))
        }
        let combined = FocusLane.concatenate(parts)
        todayIntervals = combined.intervals
        todayLength = combined.length
        let fromSamples = SankeyFlow.make(samples: samples, rules: rules, fallbackInterval: fallback)
        todaySankey = fromSamples.nodes.isEmpty ? SankeyFlow.make(intervals: combined.intervals) : fromSamples
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: TempoRadius.column, style: .continuous)
            .fill(.quaternary.opacity(0.22))
    }

    private var primaryTitle: LocalizedStringKey {
        switch model.clock.runState {
        case .running: "Pause"
        case .paused: "Start"
        case .idle: "Start"
        }
    }

    private func primaryAction() {
        if model.clock.runState == .idle, let item = model.upcomingWork(limit: 1).first {
            model.selectFocusCard(item.id)
        }
        model.toggle()
    }

    private func open(_ board: BoardOverview) {
        model.selectedBoardID = board.id
        model.section = .tasks
    }

    private var todayMinutes: Int {
        Int(
            model.facts()
                .filter { Calendar.current.isDateInToday($0.start) }
                .reduce(0) { $0 + $1.seconds } / 60
        )
    }

    private var todayPomodoros: Int {
        model.facts()
            .filter { Calendar.current.isDateInToday($0.start) && $0.counts }
            .count
    }

    private var weekDays: [HeatmapDay] {
        Array(snapshot.heatmap.flatMap(\.days).filter(\.inRange).suffix(7))
    }

    private func weekHelp(_ day: HeatmapDay) -> String {
        "\(day.day.formatted(date: .abbreviated, time: .omitted)) · \(day.minutes)"
    }
}
