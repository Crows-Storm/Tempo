import SwiftUI

struct FocusView: View {
    var model: AppModel
    var namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FocusStage(
            model: model,
            namespace: namespace,
            immersed: model.isFocusSession,
            isGeometrySource: true
        )
        .safeAreaInset(edge: .bottom) {
            if !model.isFocusSession {
                boardPicker
                    .padding(.horizontal, TempoSpacing.lg)
                    .padding(.bottom, TempoSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(model.isFocusSession ? "" : "Focus")
        .toolbar(model.isFocusSession && model.clock.boardID == nil ? .hidden : .automatic, for: .automatic)
        .animation(TempoMotion.session(reduceMotion: reduceMotion), value: model.isFocusSession)
    }

    private var boardPicker: some View {
        HStack(spacing: TempoSpacing.md) {
            Picker("Board", selection: Binding(
                get: { model.clock.boardID ?? "" },
                set: { model.setBoard($0.isEmpty ? nil : $0) }
            )) {
                Text("No Board").tag("")
                ForEach(model.fetchBoards()) { board in
                    Text(board.name).tag(board.id)
                }
                if let id = model.clock.boardID,
                   let board = model.fetchBoard(id),
                   board.archived {
                    Text(board.name).tag(board.id)
                }
            }
            Picker("Card", selection: Binding(
                get: { model.clock.cardID ?? model.selectedCardID ?? "" },
                set: { model.selectFocusCard($0.isEmpty ? nil : $0) }
            )) {
                Text("No Card").tag("")
                ForEach(cardsOnBoard) { card in
                    Text(card.title).tag(card.id)
                }
            }
            .disabled(model.clock.boardID == nil)
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 440)
    }

    private var cardsOnBoard: [CardRecord] {
        guard let boardID = model.clock.boardID else { return [] }
        return model.focusableCards(boardID: boardID)
    }
}

struct FocusStage: View {
    var model: AppModel
    var namespace: Namespace.ID
    var immersed: Bool
    var isGeometrySource: Bool = true
    @State private var confirmStop = false
    @State private var confirmShort = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer(minLength: TempoSpacing.md)
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                ZStack {
                    FocusRing(
                        progress: model.clock.progress(at: context.date, durations: model.durations),
                        tint: TempoColor.phase(model.clock.phase)
                    )
                    .frame(width: immersed ? 340 : 280, height: immersed ? 340 : 280)
                    .matchedGeometryEffect(id: "focus-ring", in: namespace, isSource: isGeometrySource)
                    .animation(TempoMotion.session(reduceMotion: reduceMotion), value: immersed)
                    VStack(spacing: TempoSpacing.xs) {
                        Text(PhaseCopy.title(model.clock.phase))
                            .font(.headline)
                            .foregroundStyle(TempoColor.secondary)
                        TimerReadout(
                            seconds: model.remaining(at: context.date),
                            phase: model.clock.phase,
                            immersed: immersed
                        )
                        .matchedGeometryEffect(id: "focus-time", in: namespace, isSource: isGeometrySource)
                    }
                }
                .onChange(of: context.date) { _, date in
                    model.reconcile(now: date)
                }
            }
            actions
            Spacer()
        }
        .padding(TempoSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Cancel discards this session.", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Cancel Session", role: .destructive) { model.cancel() }
            Button("Keep Going", role: .cancel) {}
        }
        .confirmationDialog("Complete this focus?", isPresented: $confirmShort, titleVisibility: .visible) {
            Button("Complete") { model.complete() }
            Button("Keep Focusing", role: .cancel) {}
        } message: {
            Text("Less than 10 minutes is saved as incomplete.")
        }
    }

    private var actions: some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.sm) {
                ForEach(focusActions) { action in
                    if action.prominent {
                        Button(action: action.run) {
                            Label(action.title, systemImage: action.symbol)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TempoColor.phase(model.clock.phase))
                        .disabled(action.disabled)
                        .help(action.help)
                    } else {
                        Button(role: action.destructive ? .destructive : nil, action: action.run) {
                            Label(action.title, systemImage: action.symbol)
                        }
                        .disabled(action.disabled)
                        .help(action.help)
                    }
                }
            }
            if !immersed {
                HStack(spacing: TempoSpacing.sm) {
                    Button("Extend 5 Minutes") { model.extend(minutes: 5) }
                        .disabled(model.clock.phase != .focus || model.clock.runState == .idle)
                    Button("Extend 10 Minutes") { model.extend(minutes: 10) }
                        .disabled(model.clock.phase != .focus || model.clock.runState == .idle)
                    Button("Mini Timer") { MiniTimerController.shared.toggle(model: model) }
                }
            } else {
                HStack(spacing: TempoSpacing.sm) {
                    Button("Extend 5 Minutes") { model.extend(minutes: 5) }
                        .disabled(model.clock.phase != .focus)
                    Button("Extend 10 Minutes") { model.extend(minutes: 10) }
                        .disabled(model.clock.phase != .focus)
                }
            }
        }
        .controlSize(immersed ? .large : .regular)
    }

    private var focusActions: [FocusAction] {
        switch model.clock.runState {
        case .idle:
            [
                FocusAction(id: "start", title: "Start", symbol: "play.fill", prominent: true, destructive: false, help: "Start", disabled: false, run: { model.start() }),
                FocusAction(id: "switch", title: "Switch", symbol: "arrow.left.arrow.right", prominent: false, destructive: false, help: "Switch between focus and break", disabled: false, run: { model.switchPhase() }),
                FocusAction(id: "cancel", title: "Cancel", symbol: "xmark", prominent: false, destructive: true, help: "Cancel discards this session", disabled: true, run: {}),
            ]
        case .running:
            [
                FocusAction(id: "pause", title: "Pause", symbol: "pause.fill", prominent: true, destructive: false, help: "Pause", disabled: false, run: { model.pause() }),
                FocusAction(id: "complete", title: "Complete", symbol: "checkmark", prominent: false, destructive: false, help: "Save this session", disabled: false, run: requestComplete),
                FocusAction(id: "cancel", title: "Cancel", symbol: "xmark", prominent: false, destructive: true, help: "Cancel discards this session", disabled: false, run: { confirmStop = true }),
            ]
        case .paused:
            [
                FocusAction(id: "start", title: "Start", symbol: "play.fill", prominent: true, destructive: false, help: "Resume", disabled: false, run: { model.start() }),
                FocusAction(id: "complete", title: "Complete", symbol: "checkmark", prominent: false, destructive: false, help: "Save this session", disabled: false, run: requestComplete),
                FocusAction(id: "cancel", title: "Cancel", symbol: "xmark", prominent: false, destructive: true, help: "Cancel discards this session", disabled: false, run: { confirmStop = true }),
            ]
        }
    }

    private func requestComplete() {
        let elapsed = model.clock.activeElapsed(at: .now)
        if model.clock.phase == .focus, model.clock.runState != .idle, elapsed < model.durations.rottenBefore {
            confirmShort = true
        } else {
            model.complete()
        }
    }
}

private struct FocusAction: Identifiable {
    var id: String
    var title: LocalizedStringKey
    var symbol: String
    var prominent: Bool
    var destructive: Bool
    var help: LocalizedStringKey
    var disabled: Bool
    var run: () -> Void
}

struct FinishSheet: View {
    var model: AppModel
    var prompt: FinishPrompt
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text(prompt.heading)
                .font(.title2)
            Text(TempoFormat.minutesValue(todaySeconds))
                .font(TempoFont.metric)
                .monospacedDigit()
            Text("Today")
                .foregroundStyle(TempoColor.secondary)
            if let name = prompt.suggestedBoardName, let boardID = prompt.suggestedBoardID, let sessionID = prompt.sessionID {
                Button("Add to \(name)") {
                    model.assign(sessionID: sessionID, boardID: boardID)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                Button(prompt.nextPhase == .focus ? "Start Focus" : "Start Break") {
                    dismiss()
                    model.start()
                }
                .buttonStyle(.borderedProminent)
                .tint(TempoColor.phase(prompt.nextPhase))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(TempoSpacing.lg)
        .frame(width: 420)
    }

    private var todaySeconds: TimeInterval {
        Analytics.todaySeconds(sessions: model.facts(), now: .now, calendar: .current)
    }
}

struct MiniTimerView: View {
    var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            HStack(spacing: TempoSpacing.md) {
                TimerReadout(seconds: model.remaining(at: context.date), phase: model.clock.phase, compact: true)
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text(PhaseCopy.title(model.clock.phase))
                        .foregroundStyle(TempoColor.secondary)
                    HStack(spacing: TempoSpacing.xs) {
                        Button {
                            model.toggle()
                        } label: {
                            Image(systemName: model.clock.runState == .running ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TempoColor.phase(model.clock.phase))
                        .help(model.clock.runState == .running ? "Pause" : "Start")
                        .accessibilityLabel(Text(model.clock.runState == .running ? "Pause" : "Start"))
                        if model.clock.runState != .idle {
                            Button {
                                model.complete()
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .help("Complete")
                            .accessibilityLabel(Text("Complete"))
                            Button(role: .destructive) {
                                model.cancel()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .help("Cancel")
                            .accessibilityLabel(Text("Cancel"))
                        } else {
                            Button {
                                model.switchPhase()
                            } label: {
                                Image(systemName: "arrow.left.arrow.right")
                            }
                            .help("Switch")
                            .accessibilityLabel(Text("Switch"))
                        }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    MiniTimerController.shared.toggle(model: model)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Expand")
                .accessibilityLabel(Text("Expand"))
            }
            .padding(TempoSpacing.md)
            .onChange(of: context.date) { _, date in
                model.reconcile(now: date)
            }
        }
        .frame(minWidth: 320, minHeight: 88)
    }
}