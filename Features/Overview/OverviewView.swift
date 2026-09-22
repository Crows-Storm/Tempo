import SwiftUI

struct OverviewView: View {
    @Bindable var model: AppModel
    @State private var snapshot = StatisticsSnapshot.empty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                nowAndToday
                nextWork
                boards
                recent
            }
            .padding(TempoSpacing.lg)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .navigationTitle("Overview")
        .tempoSearchable(text: $model.searchText, nonce: model.searchFocusNonce)
        .task(id: model.revision) { reload() }
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

    private var recent: some View {
        let sessions = Array(model.facts().prefix(5))
        return VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("Recent")
                .font(.headline)
            if sessions.isEmpty {
                Text("What you focus on shows up here.")
                    .foregroundStyle(TempoColor.secondary)
            } else {
                ForEach(sessions) { session in
                    Button {
                        model.selectedSessionID = session.id
                        model.historyDay = Calendar.current.startOfDay(for: session.start)
                        model.section = .history
                    } label: {
                        HStack {
                            Text(session.start.formatted(date: .abbreviated, time: .shortened))
                            if let name = boardName(session.boardID) {
                                Text(name)
                                    .foregroundStyle(TempoColor.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(TempoFormat.minutesValue(session.seconds))
                                .foregroundStyle(TempoColor.secondary)
                                .monospacedDigit()
                        }
                        .font(.callout)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(session.start.formatted(date: .abbreviated, time: .shortened)))
                    .accessibilityValue(Text(TempoFormat.spoken(session.seconds)))
                }
            }
        }
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

    private func boardName(_ id: String?) -> String? {
        guard let id else { return nil }
        return model.fetchBoard(id)?.name
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
