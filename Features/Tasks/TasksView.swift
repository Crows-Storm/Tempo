import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TasksView: View {
    @Bindable var model: AppModel
    @State private var pendingDelete: CardRecord?
    @State private var dropProbe: DropProbe?
    @State private var draggingID: String?
    @State private var cardHeights: [String: CGFloat] = [:]
    @State private var framesByList: [String: [CardFrame]] = [:]

    var body: some View {
        let revision = model.revision
        Group {
            if let boardID = model.selectedBoardID, let board = model.fetchBoard(boardID) {
                boardView(board, revision: revision)
            } else {
                boardList
            }
        }
        .navigationTitle(model.selectedBoardID == nil ? "Tasks" : (model.fetchBoard(model.selectedBoardID ?? "")?.name ?? "Tasks"))
        .tempoSearchable(text: $model.searchText, nonce: model.searchFocusNonce)
        .toolbar { toolbar }
        .onChange(of: draggingID) { _, id in
            if id == nil { dropProbe = nil }
        }
        .onChange(of: revision) { _, _ in
            draggingID = nil
            dropProbe = nil
        }
        .onChange(of: model.cardDraft) { _, draft in
            if draft != nil {
                draggingID = nil
                dropProbe = nil
            }
        }
        .background {
            CardDragMouseUpInstaller(isDragging: draggingID != nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoCardDragMouseUp)) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                draggingID = nil
                dropProbe = nil
            }
        }
        .alert("Delete this card?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { model.deleteCard(pendingDelete.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var boardList: some View {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = model.boardOverviews(includeArchived: true).filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
        let active = all.filter { !$0.archived }
        let archived = all.filter(\.archived)
        return Group {
            if model.fetchBoards(includeArchived: true).isEmpty {
                EmptyState(
                    systemImage: "checklist",
                    title: "No boards yet",
                    message: "Create a board to keep work next to the timer.",
                    actionTitle: "New Board"
                ) { model.showNewBoard = true }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                        LazyVGrid(columns: BoardGrid.columns, spacing: TempoSpacing.md) {
                            ForEach(active) { board in
                                boardCard(board)
                            }
                            NewBoardCard { model.showNewBoard = true }
                        }
                        if !archived.isEmpty {
                            Text("Archived")
                                .font(.headline)
                                .foregroundStyle(TempoColor.secondary)
                            LazyVGrid(columns: BoardGrid.columns, spacing: TempoSpacing.md) {
                                ForEach(archived) { board in
                                    boardCard(board)
                                }
                            }
                        }
                    }
                    .padding(TempoSpacing.lg)
                    .frame(maxWidth: 1080, alignment: .leading)
                }
            }
        }
    }

    private func boardCard(_ board: BoardOverview) -> some View {
        BoardCard(
            board: board,
            action: { model.selectedBoardID = board.id },
            pin: { model.togglePin(board.id) },
            archive: { model.archiveBoard(board.id) },
            unarchive: { model.unarchiveBoard(board.id) },
            delete: { model.deleteBoard(board.id) }
        )
    }

    private func boardView(_ board: BoardRecord, revision: Int) -> some View {
        let lists = model.fetchLists(boardID: board.id)
        return HStack(alignment: .top, spacing: TempoSpacing.md) {
            ForEach(lists) { list in
                column(list, revision: revision)
                    .frame(maxWidth: .infinity)
            }
            addColumn(board)
        }
        .padding(TempoSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .id("board-\(board.id)-\(revision)")
    }

    private func column(_ list: ListRecord, revision: Int) -> some View {
        let cards = model.fetchCards(listID: list.id).filter {
            TagParser.matches(query: model.searchText, title: $0.title, notes: $0.notes)
        }
        let showingDrop = CardDropTarget.showsPlaceholder(
            draggingID: draggingID,
            probeListID: dropProbe?.listID,
            columnID: list.id
        )
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                columnTitle(list)
                Spacer()
                Text("\(cards.count)")
                    .font(.caption)
                    .foregroundStyle(TempoColor.secondary)
                    .accessibilityLabel(Text("\(cards.count) cards"))
                if list.role.canDelete {
                    Button {
                        model.deleteList(list.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Delete"))
                }
            }
            .padding(TempoSpacing.sm)
            Divider()
            ScrollView {
                let space = "kanban-\(list.id)"
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    cardStack(cards, space: space, showingDrop: showingDrop)
                    if showingDrop, dropProbe?.beforeID == nil {
                        insertionSlot(height: dragSlotHeight)
                    }
                    newCardButton(list)
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .accessibilityHidden(true)
                }
                .padding(TempoSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
                .contentShape(Rectangle())
                .coordinateSpace(name: space)
                .onPreferenceChange(CardFrameKey.self) { frames in
                    for frame in frames where frame.height > 1 {
                        cardHeights[frame.id] = frame.height
                    }
                    framesByList[list.id] = frames
                }
                .onDrop(
                    of: [UTType.utf8PlainText],
                    delegate: ColumnDropDelegate(
                        listID: list.id,
                        frames: framesByList[list.id] ?? [],
                        draggingID: $draggingID,
                        slotHeight: dragSlotHeight,
                        probe: $dropProbe,
                        onMove: { id, before in
                            withAnimation(.smooth(duration: 0.28)) {
                                model.moveCard(id, to: list.id, before: before)
                            }
                            draggingID = nil
                            dropProbe = nil
                        }
                    )
                )
                .animation(.smooth(duration: 0.28), value: cards.map(\.id))
                .id("cards-\(list.id)-\(revision)-\(cards.map(\.id).joined(separator: ","))")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: TempoRadius.column)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func columnTitle(_ list: ListRecord) -> some View {
        if list.role.canRename {
            TextField("Title", text: Binding(
                get: { list.title },
                set: { model.renameList(list.id, to: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.headline)
        } else {
            Text(presetTitle(list.role))
                .font(.headline)
                .foregroundStyle(TempoColor.label)
        }
    }

    private func presetTitle(_ role: ListRole) -> LocalizedStringKey {
        switch role {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        case .custom: "New Column"
        }
    }

    private func newCardButton(_ list: ListRecord) -> some View {
        Button {
            model.cardDraft = CardDraft(
                id: UUID().uuidString,
                existingID: nil,
                listID: list.id,
                title: "",
                notes: "",
                estimatedHours: 1
            )
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
                .foregroundStyle(TempoColor.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TempoSpacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: TempoRadius.control, style: .continuous)
                        .fill(.quaternary.opacity(0.16))
                        .overlay {
                            RoundedRectangle(cornerRadius: TempoRadius.control, style: .continuous)
                                .strokeBorder(
                                    Color(nsColor: .separatorColor).opacity(0.7),
                                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                                )
                        }
                }
        }
        .buttonStyle(.plain)
        .help("New Card")
        .accessibilityLabel(Text("New Card"))
    }

    @ViewBuilder
    private func cardStack(_ cards: [CardRecord], space: String, showingDrop: Bool) -> some View {
        ForEach(cards, id: \.id) { card in
            cardCell(card, space: space, showingDrop: showingDrop)
        }
    }

    private func cardCell(_ card: CardRecord, space: String, showingDrop: Bool) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            if showingDrop, dropProbe?.beforeID == card.id {
                insertionSlot(height: dragSlotHeight)
            }
            cardRow(card)
                .opacity(draggingID == card.id ? 0.4 : 1)
                .onDrag {
                    draggingID = card.id
                    return NSItemProvider(object: card.id as NSString)
                }
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CardFrameKey.self,
                            value: [CardFrame(
                                id: card.id,
                                minY: geo.frame(in: .named(space)).minY,
                                height: geo.size.height
                            )]
                        )
                    }
                }
        }
    }

    private var dragSlotHeight: CGFloat {
        if let draggingID, let height = cardHeights[draggingID], height > 1 {
            return height
        }
        return 88
    }

    private func insertionSlot(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: TempoRadius.control, style: .continuous)
            .strokeBorder(TempoColor.info.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .background {
                RoundedRectangle(cornerRadius: TempoRadius.control, style: .continuous)
                    .fill(TempoColor.info.opacity(0.08))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                removal: .opacity
            ))
            .accessibilityHidden(true)
    }

    private func addColumn(_ board: BoardRecord) -> some View {
        Button {
            model.addColumn(boardID: board.id)
        } label: {
            VStack(spacing: TempoSpacing.xs) {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(TempoColor.secondary)
                Text("Add Column")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(TempoColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay {
            RoundedRectangle(cornerRadius: TempoRadius.column)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .help("Add Column")
        .accessibilityLabel(Text("Add Column"))
    }

    private func cardRow(_ card: CardRecord) -> some View {
        BoardCardRow(
            card: card,
            focusMinutes: model.settings.focusMinutes,
            onEdit: { edit(card) },
            onDelete: { requestDelete(card) },
            onToggleTask: { model.toggleCardTask(id: card.id, at: $0) }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let boardID = model.selectedBoardID, let board = model.fetchBoard(boardID) {
            ToolbarItem(placement: .navigation) {
                Button("All Boards") { model.selectedBoardID = nil }
            }
            ToolbarItem(placement: .primaryAction) {
                if board.archived {
                    Button {
                        model.unarchiveBoard(boardID)
                    } label: {
                        Image(systemName: "archivebox.fill")
                    }
                    .help("Unarchive")
                    .accessibilityLabel(Text("Unarchive"))
                } else {
                    Button {
                        model.archiveBoard(boardID)
                    } label: {
                        Image(systemName: "archivebox")
                    }
                    .disabled(!model.canArchive(boardID))
                    .help(model.canArchive(boardID) ? "Archive" : "Archive when every card is in Done")
                    .accessibilityLabel(Text("Archive"))
                    .accessibilityHint(Text("Available when every card is in Done."))
                }
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showNewBoard = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Board")
                .accessibilityLabel(Text("New Board"))
            }
        }
    }

    private func edit(_ card: CardRecord) {
        model.selectedCardID = card.id
        model.cardDraft = CardDraft(
            id: card.id,
            existingID: card.id,
            listID: card.listID,
            title: card.title,
            notes: card.notes,
            estimatedHours: card.estimatedHours
        )
    }

    private func requestDelete(_ card: CardRecord) {
        model.selectedCardID = card.id
        if model.settings.confirmDeleteCard {
            pendingDelete = card
        } else {
            model.deleteCard(card.id)
        }
    }
}

private struct DropProbe: Equatable {
    var listID: String
    var beforeID: String?
}

private struct CardFrameKey: PreferenceKey {
    static var defaultValue: [CardFrame] { [] }

    static func reduce(value: inout [CardFrame], nextValue: () -> [CardFrame]) {
        value.append(contentsOf: nextValue())
    }
}

private struct ColumnDropDelegate: DropDelegate {
    var listID: String
    var frames: [CardFrame]
    @Binding var draggingID: String?
    var slotHeight: CGFloat
    @Binding var probe: DropProbe?
    var onMove: (String, String?) -> Void

    func validateDrop(info _: DropInfo) -> Bool {
        draggingID != nil
    }

    func dropEntered(info: DropInfo) {
        updateProbe(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateProbe(info)
        return draggingID == nil ? nil : DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        if probe?.listID == listID {
            probe = nil
        }
    }

    func performDrop(info _: DropInfo) -> Bool {
        guard let id = draggingID else { return false }
        let before = probe?.listID == listID ? probe?.beforeID : nil
        onMove(id, before)
        draggingID = nil
        probe = nil
        return true
    }

    private func updateProbe(_ info: DropInfo) {
        guard draggingID != nil else { return }
        let next = CardDropTarget.beforeID(
            y: info.location.y,
            frames: frames,
            draggingID: draggingID,
            holdingBefore: probe?.listID == listID ? probe?.beforeID : nil,
            holdingThisColumn: probe?.listID == listID,
            gap: slotHeight
        )
        let updated = DropProbe(listID: listID, beforeID: next)
        guard probe != updated else { return }
        withAnimation(.smooth(duration: 0.2)) {
            probe = updated
        }
    }
}

private extension Notification.Name {
    static let tempoCardDragMouseUp = Notification.Name("tempo.cardDragMouseUp")
}

private struct CardDragMouseUpInstaller: NSViewRepresentable {
    var isDragging: Bool

    func makeNSView(context: Context) -> NSView {
        context.coordinator.setDragging(isDragging)
        return NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setDragging(isDragging)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: @unchecked Sendable {
        private var monitor: Any?

        func setDragging(_ dragging: Bool) {
            if dragging {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                    NotificationCenter.default.post(name: .tempoCardDragMouseUp, object: nil)
                    return event
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

private struct BoardCardRow: View {
    var card: CardRecord
    var focusMinutes: Int
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onToggleTask: (Int) -> Void
    @State private var suppressEdit = false

    var body: some View {
        let done = CardEffort.donePomodoros(
            sessionIDsJSON: card.sessionIDsJSON,
            actualHours: card.actualHours,
            focusMinutes: focusMinutes
        )
        let planned = CardEffort.plannedPomodoros(
            estimatedHours: card.estimatedHours,
            focusMinutes: focusMinutes
        )
        Button {
            guard !suppressEdit else {
                suppressEdit = false
                return
            }
            onEdit()
        } label: {
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text(card.title)
                    .font(.headline)
                    .foregroundStyle(TempoColor.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !card.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MarkdownPreview(source: card.notes, lineLimit: 4, compact: true) { index in
                        suppressEdit = true
                        onToggleTask(index)
                    }
                }
                CardEffortMeter(
                    actualHours: card.actualHours,
                    estimatedHours: card.estimatedHours,
                    donePomodoros: done,
                    plannedPomodoros: planned
                )
                let tags = TagParser.tags(in: card.title + " " + card.notes)
                if !tags.isEmpty {
                    Text(tags.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(TempoColor.info)
                        .lineLimit(2)
                }
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: TempoRadius.control, style: .continuous)
                    .fill(.quaternary.opacity(0.28))
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit") { onEdit() }
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityLabel(Text(card.title))
        .accessibilityValue(Text("\(done) / \(planned), \(TempoFormat.spoken(card.actualHours * 3600))"))
        .accessibilityHint(Text("Shows the card."))
    }
}

struct CardEditor: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var estimatedHours = 1.0
    @State private var notesMode: NotesMode = .write
    @FocusState private var titleFocused: Bool

    private enum NotesMode: String, CaseIterable, Identifiable {
        case write
        case preview
        var id: String { rawValue }
        var titleKey: LocalizedStringKey {
            switch self {
            case .write: "Write"
            case .preview: "Preview"
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text(model.cardDraft?.existingID == nil ? "New Card" : "Edit")
                .font(.title2)
            TextField("Title", text: $title)
                .focused($titleFocused)
                .onSubmit(save)
            Picker("Notes", selection: $notesMode) {
                ForEach(NotesMode.allCases) { mode in
                    Text(mode.titleKey).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if notesMode == .write {
                TextEditor(text: $notes)
                    .font(.body)
                    .frame(minHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("Notes")
                                .foregroundStyle(TempoColor.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                ScrollView {
                    if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Notes")
                            .foregroundStyle(TempoColor.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MarkdownPreview(source: notes) { index in
                            notes = MarkdownTasks.toggle(in: notes, at: index)
                        }
                    }
                }
                .frame(minHeight: 180)
            }
            Text(TagParser.tags(in: title + " " + notes).joined(separator: " "))
                .font(.caption)
                .foregroundStyle(TempoColor.info)
            LabeledContent("Estimated") {
                TextField("Estimated", value: $estimatedHours, format: .number)
                    .frame(width: 80)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cardDraft = nil }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(TempoColor.info)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(TempoSpacing.lg)
        .frame(width: 560)
        .onAppear {
            title = model.cardDraft?.title ?? ""
            notes = model.cardDraft?.notes ?? ""
            estimatedHours = model.cardDraft?.estimatedHours ?? 1
            titleFocused = true
        }
    }

    private func save() {
        guard canSave else { return }
        guard var draft = model.cardDraft else { return }
        draft.title = title
        draft.notes = notes
        draft.estimatedHours = estimatedHours
        model.cardDraft = draft
        model.saveDraft()
        dismiss()
    }
}

struct NewBoardSheet: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("New Board")
                .font(.title2)
            TextField("Title", text: $name)
                .focused($titleFocused)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(TempoColor.info)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(TempoSpacing.lg)
        .frame(width: 360)
        .onAppear { titleFocused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.createBoard(name: trimmed)
        dismiss()
    }
}
