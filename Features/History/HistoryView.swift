import Charts
import SwiftUI

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var lanes: [String: [FocusInterval]] = [:]
    @State private var detailSamples: [ActivitySample] = []

    var body: some View {
        HSplitView {
            browser
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, maxHeight: .infinity)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("History")
        .tempoSearchable(text: $model.searchText, nonce: model.searchFocusNonce)
        .toolbar {
            ToolbarItem {
                Picker("Board", selection: Binding(
                    get: { model.historyBoardID ?? "" },
                    set: { model.historyBoardID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("All Boards").tag("")
                    ForEach(model.fetchBoards(includeArchived: true)) { board in
                        Text(board.name).tag(board.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .task(id: laneKey) { await loadLanes() }
        .task(id: selectedSession?.id) { await loadDetailSamples() }
        .onAppear {
            if model.historyDay == nil { model.historyDay = Date() }
        }
    }

    private var browser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                MonthCalendar(sessions: filtered, selected: model.historyDay ?? .now, select: selectDay)
                sessions
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
    }

    private var sessions: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text((model.historyDay ?? .now).formatted(date: .long, time: .omitted))
                .font(.headline)
            if scopedSessions.isEmpty {
                Text("No sessions this day")
                    .foregroundStyle(TempoColor.secondary)
            } else {
                ForEach(scopedSessions) { session in
                    Button {
                        model.selectedSessionID = session.id
                    } label: {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TempoColor.label)
                    .padding(TempoSpacing.sm)
                    .background(sessionBackground(selected: session.id == selectedSession?.id))
                    .accessibilityAddTraits(session.id == selectedSession?.id ? .isSelected : [])
                    .accessibilityLabel(Text(session.start.formatted(date: .omitted, time: .shortened)))
                    .accessibilityValue(Text(TempoFormat.spoken(session.seconds)))
                }
            }
        }
    }

    private func sessionRow(_ session: SessionFact) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.start.formatted(date: .omitted, time: .shortened))
                    .font(.body.weight(.semibold))
                if session.rotten {
                    Text("Incomplete")
                        .font(.caption)
                        .foregroundStyle(TempoColor.secondary)
                }
                Spacer()
                Text(TempoFormat.minutesValue(session.seconds))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(TempoColor.secondary)
            }
            PomodoroLaneChart(
                intervals: lanes[session.id] ?? [],
                length: session.seconds,
                height: 22
            )
            Text(subtitleApp(session))
                .font(.caption)
                .foregroundStyle(TempoColor.secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    private func sessionBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: TempoRadius.column, style: .continuous)
            .fill(Color.primary.opacity(selected ? 0.12 : 0.055))
            .overlay {
                RoundedRectangle(cornerRadius: TempoRadius.column, style: .continuous)
                    .strokeBorder(selected ? TempoColor.info.opacity(0.45) : .clear, lineWidth: 1)
            }
    }

    @ViewBuilder
    private var detail: some View {
        if let session = selectedSession {
            SessionDetail(
                session: session,
                intervals: lanes[session.id] ?? [],
                samples: detailSamples,
                boardName: boardName(session.boardID),
                rules: model.settings.distractionRules,
                fallback: model.settings.monitorInterval
            )
        } else {
            ContentUnavailableView(
                "Pick a pomodoro",
                systemImage: "clock",
                description: Text("Each session is a picture of where attention went.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filtered: [SessionFact] {
        model.facts().filter { session in
            if let board = model.historyBoardID, session.boardID != board { return false }
            if !model.searchText.isEmpty {
                let hay = (session.primaryApp ?? "") + " " + session.titles.map(\.title).joined(separator: " ")
                if !hay.localizedStandardContains(model.searchText) { return false }
            }
            return true
        }
    }

    private var scopedSessions: [SessionFact] {
        guard let day = model.historyDay else { return filtered }
        return filtered.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    private var selectedSession: SessionFact? {
        scopedSessions.first(where: { $0.id == model.selectedSessionID }) ?? scopedSessions.first
    }

    private var laneKey: String {
        scopedSessions.map(\.id).joined(separator: ",") + "-\(model.revision)"
    }

    private func selectDay(_ day: Date) {
        model.historyDay = day
        model.selectedSessionID = filtered.first(where: { Calendar.current.isDate($0.start, inSameDayAs: day) })?.id
    }

    private func boardName(_ id: String?) -> String? {
        guard let id, let board = model.fetchBoard(id) else { return nil }
        return board.name
    }

    private func loadLanes() async {
        var next: [String: [FocusInterval]] = [:]
        for session in scopedSessions {
            let samples = (try? await model.activity.samples(sessionID: session.id)) ?? []
            next[session.id] = FocusLane.make(
                samples: samples,
                session: session,
                rules: model.settings.distractionRules,
                fallback: model.settings.monitorInterval
            )
        }
        lanes = next
        if model.selectedSessionID == nil {
            model.selectedSessionID = scopedSessions.first?.id
        }
    }

    private func subtitleApp(_ session: SessionFact) -> String {
        if let name = session.primaryApp, !SystemChrome.isIgnored(appName: name) {
            return name
        }
        if let name = session.apps.first(where: { !SystemChrome.isIgnored(appName: $0.name) })?.name {
            return name
        }
        return session.primaryApp ?? String(localized: "Focus")
    }

    private func loadDetailSamples() async {
        guard let id = selectedSession?.id else {
            detailSamples = []
            return
        }
        detailSamples = (try? await model.activity.samples(sessionID: id)) ?? []
    }
}

struct SessionDetail: View {
    var session: SessionFact
    var intervals: [FocusInterval]
    var samples: [ActivitySample]
    var boardName: String?
    var rules: [DistractionRule]
    var fallback: TimeInterval

    var body: some View {
        let focused = FocusLane.focusedSeconds(intervals)
        let distracted = FocusLane.distractedSeconds(intervals)
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text(session.start.formatted(date: .complete, time: .shortened))
                        .font(.title2)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: TempoSpacing.md, alignment: .leading)],
                        alignment: .leading,
                        spacing: TempoSpacing.sm
                    ) {
                        LabeledContent("Focus time", value: TempoFormat.minutesValue(session.seconds))
                        if let boardName {
                            LabeledContent("Board", value: boardName)
                        }
                        if session.rotten {
                            LabeledContent("Status", value: String(localized: "Incomplete"))
                        }
                        if let efficiency = session.efficiency {
                            LabeledContent("Efficiency", value: efficiency.formatted(.percent.precision(.fractionLength(0))))
                                .help("Efficiency is the share of samples that did not match your distraction list.")
                        }
                    }
                    .font(.body)
                }
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("This session")
                        .font(.headline)
                    PomodoroLaneChart(
                        intervals: intervals,
                        length: session.seconds,
                        height: 52,
                        showsAxis: true
                    )
                    appLegend
                }
                AttentionStrip(focused: focused, distracted: distracted)
                SessionSankey(diagram: sankey)
            }
            .padding(TempoSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sankey: SankeyDiagram {
        let fromSamples = SankeyFlow.make(samples: samples, rules: rules, fallbackInterval: fallback)
        if !fromSamples.nodes.isEmpty { return fromSamples }
        return SankeyFlow.make(intervals: intervals)
    }

    private var appLegend: some View {
        let apps = Dictionary(grouping: intervals, by: \.app)
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
}
