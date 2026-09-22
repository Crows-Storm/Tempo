import SwiftUI

struct FocusSessionSidebar: View {
    @Bindable var model: AppModel
    @State private var browseList = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = model.revision
        Group {
            if let boardID = model.clock.boardID, let board = model.fetchBoard(boardID) {
                let cards = model.inProgressCards(boardID: boardID)
                if let card = selectedCard(from: cards), !browseList {
                    FocusCardDetail(model: model, board: board, card: card) {
                        withAnimation(TempoMotion.session(reduceMotion: reduceMotion)) {
                            browseList = true
                        }
                    }
                    .transition(paneTransition(push: true))
                } else {
                    FocusInProgressList(model: model, board: board, cards: cards, selectedID: model.clock.cardID) { id in
                        withAnimation(TempoMotion.session(reduceMotion: reduceMotion)) {
                            browseList = false
                            model.selectFocusCard(id)
                        }
                    }
                    .transition(paneTransition(push: false))
                }
            } else {
                Color.clear
            }
        }
        .animation(TempoMotion.session(reduceMotion: reduceMotion), value: browseList)
        .animation(TempoMotion.session(reduceMotion: reduceMotion), value: model.clock.cardID)
    }

    private func selectedCard(from cards: [CardRecord]) -> CardRecord? {
        guard let id = model.clock.cardID else { return nil }
        return cards.first { $0.id == id }
    }

    private func paneTransition(push: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        let edge: Edge = push ? .trailing : .leading
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: edge)),
            removal: .opacity.combined(with: .move(edge: edge))
        )
    }
}

private struct FocusInProgressList: View {
    var model: AppModel
    var board: BoardRecord
    var cards: [CardRecord]
    var selectedID: String?
    var onOpen: (String) -> Void

    var body: some View {
        List {
            Section {
                if cards.isEmpty {
                    Text("No in-progress cards")
                        .foregroundStyle(TempoColor.secondary)
                } else {
                    ForEach(cards) { card in
                        Button {
                            onOpen(card.id)
                        } label: {
                            FocusCardRow(card: card, focusMinutes: model.settings.focusMinutes)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(card.id == selectedID ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                }
            } header: {
                Text("In Progress")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(board.name)
    }
}

private struct FocusCardDetail: View {
    var model: AppModel
    var board: BoardRecord
    var card: CardRecord
    var showBoard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: showBoard) {
                Label("In Progress", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, TempoSpacing.sm)
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    Text(card.title)
                        .font(.title2)
                        .textSelection(.enabled)
                    CardEffortMeter(
                        actualHours: card.actualHours,
                        estimatedHours: card.estimatedHours,
                        donePomodoros: CardEffort.donePomodoros(
                            sessionIDsJSON: card.sessionIDsJSON,
                            actualHours: card.actualHours,
                            focusMinutes: model.settings.focusMinutes
                        ),
                        plannedPomodoros: CardEffort.plannedPomodoros(
                            estimatedHours: card.estimatedHours,
                            focusMinutes: model.settings.focusMinutes
                        )
                    )
                    if card.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("No notes")
                            .foregroundStyle(TempoColor.secondary)
                    } else {
                        MarkdownPreview(source: card.notes)
                    }
                }
                .padding(TempoSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle(board.name)
    }
}

private struct FocusCardRow: View {
    var card: CardRecord
    var focusMinutes: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.title)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: TempoSpacing.xs) {
                Text(TempoFormat.minutesValue(card.actualHours * 3600))
                Text("·")
                Text("\(CardEffort.donePomodoros(sessionIDsJSON: card.sessionIDsJSON, actualHours: card.actualHours, focusMinutes: focusMinutes)) / \(CardEffort.plannedPomodoros(estimatedHours: card.estimatedHours, focusMinutes: focusMinutes))")
            }
            .font(.caption)
            .foregroundStyle(TempoColor.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(card.title))
    }
}
