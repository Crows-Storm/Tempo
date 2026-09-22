import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case focus
    case tasks
    case history
    case statistics

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .overview: "Overview"
        case .focus: "Focus"
        case .tasks: "Tasks"
        case .history: "History"
        case .statistics: "Statistics"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .focus: "timer"
        case .tasks: "checklist"
        case .history: "clock"
        case .statistics: "chart.bar"
        }
    }

    var number: Int {
        switch self {
        case .overview: 1
        case .focus: 2
        case .tasks: 3
        case .history: 4
        case .statistics: 5
        }
    }
}

enum FocusSplitVisibility {
    static func resolved(
        isFocusSession: Bool,
        hasBoard: Bool,
        sessionHidesSidebar: Bool,
        idle: NavigationSplitViewVisibility
    ) -> NavigationSplitViewVisibility {
        guard isFocusSession else { return idle }
        if hasBoard && !sessionHidesSidebar { return .all }
        return .detailOnly
    }

    static func sessionHidesSidebar(
        current: Bool,
        isFocusSession: Bool,
        hasBoard: Bool,
        newValue: NavigationSplitViewVisibility
    ) -> Bool {
        guard isFocusSession, hasBoard else { return current }
        return newValue == .detailOnly
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Namespace private var focusChrome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sessionHidesSidebar = false

    var body: some View {
        Group {
            if model.isMiniTimer {
                MiniTimerView(model: model)
            } else {
                split
                    .animation(TempoMotion.session(reduceMotion: reduceMotion), value: model.isFocusSession)
                    .animation(TempoMotion.session(reduceMotion: reduceMotion), value: model.clock.boardID)
                    .animation(TempoMotion.session(reduceMotion: reduceMotion), value: sessionHidesSidebar)
            }
        }
        .background(MainWindowConfigurator())
        .sheet(isPresented: $model.showWelcome) {
            WelcomeSheet { model.dismissWelcome() }
        }
        .sheet(isPresented: $model.showHelp) {
            ShortcutsSheet()
        }
        .sheet(item: $model.finishPrompt) { prompt in
            FinishSheet(model: model, prompt: prompt)
        }
        .sheet(item: $model.cardDraft) { _ in
            CardEditor(model: model)
        }
        .sheet(isPresented: $model.showNewBoard) {
            NewBoardSheet(model: model)
        }
        .alert("Tempo", isPresented: Binding(
            get: { model.statusMessage != nil },
            set: { if !$0 { model.statusMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.statusMessage = nil }
        } message: {
            Text(model.statusMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.reconcile()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            model.reconcile()
        }
        .animation(TempoMotion.change(reduceMotion: reduceMotion), value: model.section)
        .onChange(of: model.section) { _, _ in
            if !model.isFocusSession, model.columnVisibility == .detailOnly {
                model.columnVisibility = .automatic
            }
        }
        .onChange(of: model.isFocusSession) { _, session in
            if session { sessionHidesSidebar = false }
        }
        .onAppear {
            MenuBarController.shared.install(model: model)
        }
    }

    private var split: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 560)
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: {
                FocusSplitVisibility.resolved(
                    isFocusSession: model.isFocusSession,
                    hasBoard: model.clock.boardID != nil,
                    sessionHidesSidebar: sessionHidesSidebar,
                    idle: model.columnVisibility
                )
            },
            set: { newValue in
                if model.isFocusSession {
                    sessionHidesSidebar = FocusSplitVisibility.sessionHidesSidebar(
                        current: sessionHidesSidebar,
                        isFocusSession: true,
                        hasBoard: model.clock.boardID != nil,
                        newValue: newValue
                    )
                } else {
                    model.columnVisibility = newValue
                }
            }
        )
    }

    @ViewBuilder
    private var sidebar: some View {
        if model.isFocusSession {
            FocusSessionSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } else {
            List(selection: $model.section) {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.titleKey, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .navigationTitle("Tempo")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.isFocusSession || model.section == .focus {
            FocusView(model: model, namespace: focusChrome)
        } else {
            switch model.section {
            case .overview: OverviewView(model: model)
            case .focus: EmptyView()
            case .tasks: TasksView(model: model)
            case .history: HistoryView(model: model)
            case .statistics: StatisticsView(model: model)
            }
        }
    }
}

struct TempoCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SettingsWindowController.show(model: model)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Card") { model.createCardFromCommand() }
                .keyboardShortcut("n")
            Button("New Board") { model.showNewBoard = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { model.requestSearchFocus() }
                .keyboardShortcut("f", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            ForEach(SidebarSection.allCases) { section in
                Button(section.titleKey) { model.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(section.number)")), modifiers: .command)
            }
        }
        CommandMenu("Focus") {
            Button(model.clock.runState == .running ? "Pause" : "Start") { model.toggle() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Switch") { model.switchPhase() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model.clock.runState != .idle)
            Button("Complete") { model.complete() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.clock.runState == .idle)
            Button("Cancel") { model.cancel() }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(model.clock.runState == .idle)
            Divider()
            Button("Extend 5 Minutes") { model.extend(minutes: 5) }
                .disabled(model.clock.phase != .focus || model.clock.runState == .idle)
            Button("Extend 10 Minutes") { model.extend(minutes: 10) }
                .disabled(model.clock.phase != .focus || model.clock.runState == .idle)
            Button("Mini Timer") { MiniTimerController.shared.toggle(model: model) }
        }
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") { model.showHelp = true }
                .keyboardShortcut("?", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
            Button("Delete") { if let id = model.selectedCardID { model.deleteCard(id) } }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.selectedCardID == nil)
        }
    }
}

struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("Keyboard Shortcuts")
                .font(.title2)
            Grid(alignment: .leading, horizontalSpacing: TempoSpacing.lg, verticalSpacing: TempoSpacing.xs) {
                row("Start or Pause", "Space")
                row("Switch Focus or Break", "⌥⌘S")
                row("Complete", "⇧⌘S")
                row("Cancel Session", "⇧⌘.")
                row("New Card", "⌘N")
                row("New Board", "⇧⌘N")
                row("Find", "⌘F")
                row("Settings", "⌘,")
                row("Overview", "⌘1")
                row("Focus", "⌘2")
                row("Tasks", "⌘3")
                row("History", "⌘4")
                row("Statistics", "⌘5")
            }
            .font(.body)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(TempoSpacing.lg)
        .frame(width: 420)
    }

    private func row(_ name: LocalizedStringKey, _ keys: String) -> some View {
        GridRow {
            Text(name)
            Text(keys).foregroundStyle(.secondary).monospaced()
        }
    }
}
