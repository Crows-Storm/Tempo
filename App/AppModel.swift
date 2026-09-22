import AppKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct FinishPrompt: Identifiable, Equatable {
    var id: String
    var heading: String
    var sessionID: String?
    var suggestedBoardID: String?
    var suggestedBoardName: String?
    var nextPhase: FocusPhase
}

struct CardDraft: Identifiable, Equatable {
    var id: String
    var existingID: String?
    var listID: String
    var title: String
    var notes: String
    var estimatedHours: Double
}

@MainActor
@Observable
final class AppModel {
    let container: ModelContainer
    let activity: ActivityLog
    let folder: URL

    var clock: FocusClock
    @ObservationIgnored
    private var storedSettings: AppSettings
    var settings: AppSettings {
        get {
            access(keyPath: \.settings)
            return storedSettings
        }
        set {
            let previousAppearance = storedSettings.appearance
            withMutation(keyPath: \.settings) {
                storedSettings = newValue
            }
            newValue.save()
            if newValue.appearance != previousAppearance {
                newValue.appearance.apply()
            }
        }
    }
    var section: SidebarSection = .overview
    var selectedBoardID: String?
    var selectedCardID: String?
    var selectedSessionID: String?
    var historyDay: Date?
    var historyBoardID: String?
    var searchText = ""
    var searchFocusNonce = 0
    var finishPrompt: FinishPrompt?
    var cardDraft: CardDraft?
    var showNewBoard = false
    var showWelcome = false
    var showHelp = false
    var showClearConfirm = false
    var statusMessage: String?
    var columnVisibility: NavigationSplitViewVisibility = .automatic
    var isMiniTimer = false
    var revision = 0

    var isFocusSession: Bool { clock.runState != .idle }

    private var sampleTask: Task<Void, Never>?
    private var didImport = false

    var durations: FocusDurations { settings.durations }

    init() {
        let loaded = AppSettings.load()
        loaded.language.apply()
        storedSettings = loaded
        clock = FocusClock.load()
        let stack: TempoStack
        if let live = try? TempoStore.live() {
            stack = live
        } else if let memory = try? TempoStore.memory() {
            stack = memory
            statusMessage = String(localized: "Tempo could not open its library. This session is temporary.")
        } else {
            fatalError("Tempo could not create storage")
        }
        container = stack.container
        activity = stack.activity
        folder = stack.folder
        container.mainContext.undoManager = UndoManager()
        showWelcome = !settings.welcomed
        let event = clock.reconcile(at: .now, durations: durations)
        if event != .none {
            Task { await self.handle(event) }
        }
        Task { await self.importLegacyIfNeeded() }
        startClockWatch()
    }

    init(stack: TempoStack) {
        storedSettings = AppSettings.load()
        clock = FocusClock()
        container = stack.container
        activity = stack.activity
        folder = stack.folder
        container.mainContext.undoManager = UndoManager()
        showWelcome = false
    }

    private func startClockWatch() {
        Task { [weak self] in
            while !Task.isCancelled {
                let running = self?.clock.runState == .running
                if running == true {
                    self?.reconcile()
                }
                MenuBarController.shared.refreshTitle()
                try? await Task.sleep(for: .milliseconds(running == true ? 500 : 2_000))
            }
        }
    }

    func remaining(at now: Date = .now) -> TimeInterval {
        clock.remaining(at: now, durations: durations)
    }

    func toggle() {
        switch clock.runState {
        case .idle: start()
        case .running: pause()
        case .paused: start()
        }
    }

    func start() {
        clock.start(at: .now, durations: durations)
        clock.save()
        if clock.phase == .focus, clock.runState == .running {
            section = .focus
            startSampling()
        }
    }

    func pause() {
        clock.pause(at: .now, durations: durations)
        clock.save()
        stopSampling()
    }

    func stop() {
        let discarded = clock.stop()
        clock.budget = durations.focus
        clock.save()
        stopSampling()
        if let discarded {
            Task { try? await activity.delete(sessionID: discarded) }
        }
    }

    func switchPhase() {
        clock.switchPhase(durations: durations)
        clock.save()
    }

    func complete() {
        skip()
    }

    func cancel() {
        stop()
    }

    func skip() {
        let event = clock.skip(at: .now, durations: durations)
        clock.save()
        stopSampling()
        Task { await handle(event) }
    }

    func extend(minutes: Int) {
        clock.extend(by: TimeInterval(minutes * 60), at: .now)
        clock.save()
    }

    func reconcile(now: Date = .now) {
        let event = clock.reconcile(at: now, durations: durations)
        guard event != .none else { return }
        clock.save()
        stopSampling()
        Task { await handle(event) }
    }

    func setBoard(_ id: String?) {
        clock.boardID = id
        if id == nil || boardID(forCardID: clock.cardID) != id {
            clock.cardID = nil
            selectedCardID = nil
        }
        clock.save()
        selectedBoardID = id
    }

    func addDistractionRule() {
        var next = settings
        next.distractionRules.append(DistractionRule(id: UUID().uuidString, app: "", title: ""))
        settings = next
    }

    func removeDistractionRule(_ id: String) {
        var next = settings
        next.distractionRules.removeAll { $0.id == id }
        settings = next
    }

    func updateDistractionRule(_ id: String, app: String? = nil, title: String? = nil) {
        var next = settings
        guard let index = next.distractionRules.firstIndex(where: { $0.id == id }) else { return }
        if let app { next.distractionRules[index].app = app }
        if let title { next.distractionRules[index].title = title }
        settings = next
    }

    func boardID(for card: CardRecord) -> String? {
        fetchAllLists().first { $0.id == card.listID }?.boardID
    }

    func focusableCards(boardID: String) -> [CardRecord] {
        fetchLists(boardID: boardID)
            .filter { $0.role != .done }
            .flatMap { fetchCards(listID: $0.id) }
    }

    func inProgressCards(boardID: String) -> [CardRecord] {
        guard let board = fetchBoard(boardID) else { return [] }
        return fetchCards(listID: board.focusedListID)
    }

    func boardID(forCardID id: String?) -> String? {
        guard let id, let card = fetchCard(id) else { return nil }
        return boardID(for: card)
    }

    func selectFocusCard(_ id: String?) {
        guard let id, let card = fetchCard(id) else {
            selectedCardID = nil
            clock.cardID = nil
            clock.save()
            return
        }
        if let owner = boardID(for: card) {
            clock.boardID = owner
            selectedBoardID = owner
        }
        selectedCardID = id
        clock.cardID = id
        clock.save()
        if let boardID = clock.boardID, let board = fetchBoard(boardID), card.listID != board.focusedListID {
            moveCard(id, to: board.focusedListID)
        }
    }

    func createBoard(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? String(localized: "New Board") : trimmed
        let boardID = UUID().uuidString
        let todo = UUID().uuidString
        let progress = UUID().uuidString
        let done = UUID().uuidString
        let context = container.mainContext
        context.insert(BoardRecord(id: boardID, name: title, focusedListID: progress, doneListID: done))
        context.insert(ListRecord(id: todo, boardID: boardID, title: String(localized: "To Do"), roleRaw: ListRole.todo.rawValue, position: 0))
        context.insert(ListRecord(id: progress, boardID: boardID, title: String(localized: "In Progress"), roleRaw: ListRole.inProgress.rawValue, position: 1))
        context.insert(ListRecord(id: done, boardID: boardID, title: String(localized: "Done"), roleRaw: ListRole.done.rawValue, position: 2))
        context.insert(CardRecord(
            id: UUID().uuidString,
            listID: todo,
            title: BoardSeed.welcomeTitle,
            notes: BoardSeed.welcomeNotes,
            estimatedHours: 1
        ))
        saveContext()
        selectedBoardID = boardID
        section = .tasks
    }

    func createCardFromCommand() {
        let boards = fetchBoards()
        if boards.isEmpty {
            createBoard(name: "")
        }
        guard let board = fetchBoards().first(where: { $0.id == selectedBoardID }) ?? fetchBoards().first else { return }
        selectedBoardID = board.id
        section = .tasks
        let todo = fetchLists(boardID: board.id).first { $0.role == .todo }
        cardDraft = CardDraft(id: UUID().uuidString, existingID: nil, listID: todo?.id ?? board.focusedListID, title: "", notes: "", estimatedHours: 1)
    }

    func saveDraft() {
        guard let draft = cardDraft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let context = container.mainContext
        if let existingID = draft.existingID, let card = fetchCard(existingID) {
            card.title = title
            card.notes = draft.notes
            card.estimatedHours = draft.estimatedHours
            card.listID = draft.listID
        } else {
            let position = (fetchCards(listID: draft.listID).map(\.position).max() ?? -1) + 1
            context.insert(CardRecord(
                id: draft.existingID ?? draft.id,
                listID: draft.listID,
                title: title,
                notes: draft.notes,
                estimatedHours: draft.estimatedHours,
                position: position
            ))
        }
        saveContext()
        cardDraft = nil
    }

    func deleteCard(_ id: String) {
        guard let card = fetchCard(id) else { return }
        container.mainContext.delete(card)
        if selectedCardID == id { selectedCardID = nil }
        saveContext()
    }

    func moveCard(_ id: String, to listID: String, before beforeID: String? = nil) {
        applyCardOrder(moving: [id], to: listID, before: beforeID)
    }

    private func applyCardOrder(moving: [String], to listID: String, before beforeID: String?) {
        let cards = moving.compactMap(fetchCard)
        guard !cards.isEmpty else { return }
        let fromIDs = Set(cards.map(\.listID))
        let destinationIDs = CardOrder.inserted(
            cards.map(\.id),
            into: fetchCards(listID: listID).map(\.id),
            before: beforeID
        )
        for (index, id) in destinationIDs.enumerated() {
            guard let card = fetchCard(id) else { continue }
            let from = card.listID
            card.listID = listID
            card.position = index
            if from != listID {
                container.mainContext.insert(MoveRecord(fromListID: from, toListID: listID, cardID: id, time: .now))
            }
        }
        for fromID in fromIDs where fromID != listID {
            for (index, card) in fetchCards(listID: fromID).enumerated() {
                card.position = index
            }
        }
        saveContext()
    }

    func addColumn(boardID: String) {
        let position = (fetchLists(boardID: boardID).map(\.position).max() ?? -1) + 1
        container.mainContext.insert(ListRecord(
            id: UUID().uuidString,
            boardID: boardID,
            title: String(localized: "New Column"),
            roleRaw: ListRole.custom.rawValue,
            position: position
        ))
        saveContext()
    }

    func deleteList(_ id: String) {
        guard let list = fetchLists(boardID: nil).first(where: { $0.id == id }), list.role.canDelete else { return }
        let fallback = fetchLists(boardID: list.boardID).first { $0.role == .todo }?.id
        if let fallback {
            for card in fetchCards(listID: id) {
                moveCard(card.id, to: fallback)
            }
        }
        if let current = fetchLists(boardID: list.boardID).first(where: { $0.id == id }) {
            container.mainContext.delete(current)
        }
        saveContext()
    }

    func renameList(_ id: String, to title: String) {
        guard let list = fetchAllLists().first(where: { $0.id == id }), list.role.canRename else { return }
        list.title = title
        saveContext()
    }

    func renameBoard(_ id: String, to title: String) {
        guard let board = fetchBoard(id) else { return }
        board.name = title
        saveContext()
    }

    func togglePin(_ id: String) {
        guard let board = fetchBoard(id) else { return }
        board.pinned.toggle()
        saveContext()
    }

    func canArchive(_ id: String) -> Bool {
        guard let board = fetchBoard(id), !board.archived else { return false }
        let lists = fetchLists(boardID: id)
        let cards = lists.flatMap { fetchCards(listID: $0.id) }
        guard !cards.isEmpty else { return false }
        return cards.allSatisfy { $0.listID == board.doneListID }
    }

    func archiveBoard(_ id: String) {
        guard canArchive(id), let board = fetchBoard(id) else { return }
        board.archived = true
        if selectedBoardID == id { selectedBoardID = nil }
        saveContext()
    }

    func unarchiveBoard(_ id: String) {
        guard let board = fetchBoard(id), board.archived else { return }
        board.archived = false
        saveContext()
    }

    func deleteBoard(_ id: String) {
        let context = container.mainContext
        for list in fetchLists(boardID: id) {
            for card in fetchCards(listID: list.id) { context.delete(card) }
            context.delete(list)
        }
        if let board = fetchBoard(id) { context.delete(board) }
        if selectedBoardID == id { selectedBoardID = nil }
        saveContext()
    }

    func requestSearchFocus() {
        searchFocusNonce += 1
    }

    func assign(sessionID: String, boardID: String) {
        guard let session = fetchSessions().first(where: { $0.id == sessionID }) else { return }
        session.boardID = boardID
        attach(session: session, hours: session.spentSeconds / 3600, boardID: boardID, cardID: clock.cardID)
        saveContext()
        if finishPrompt?.sessionID == sessionID {
            finishPrompt?.suggestedBoardID = nil
        }
    }

    func importLegacyIfNeeded(force: Bool = false) async {
        let marker = LibraryImporter.markerURL(in: folder)
        if !force, FileManager.default.fileExists(atPath: marker.path) { return }
        let bundle = await Task.detached(priority: .utility) {
            LibraryImporter.loadExternal()
        }.value
        if !bundle.isEmpty {
            try? LibraryImporter.apply(bundle, context: container.mainContext, settings: &settings)
            revision += 1
        }
        let stamp = ["importedAt": Date().timeIntervalSince1970]
        if let data = try? JSONSerialization.data(withJSONObject: stamp) {
            try? data.write(to: marker, options: .atomic)
        }
        didImport = true
    }

    func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let bundle = LegacyDecoder.bundle(fromJSON: data) else {
            statusMessage = String(localized: "That file is not a Tempo export.")
            return
        }
        do {
            try LibraryImporter.apply(bundle, context: container.mainContext, settings: &settings)
            statusMessage = String(localized: "Import finished.")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "tempo-exported-data.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bundle = try LibraryImporter.exportBundle(context: container.mainContext)
            let object = LegacyDecoder.exportObject(from: bundle)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            statusMessage = String(localized: "Export finished.")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearAll() {
        let context = container.mainContext
        try? context.delete(model: BoardRecord.self)
        try? context.delete(model: ListRecord.self)
        try? context.delete(model: CardRecord.self)
        try? context.delete(model: SessionRecord.self)
        try? context.delete(model: MoveRecord.self)
        try? context.save()
        Task { try? await activity.deleteAll() }
        clock = FocusClock()
        clock.save()
        selectedBoardID = nil
        selectedCardID = nil
        selectedSessionID = nil
    }

    func dismissWelcome() {
        settings.welcomed = true
        showWelcome = false
    }

    func fetchBoards(includeArchived: Bool = false) -> [BoardRecord] {
        let boards = (try? container.mainContext.fetch(FetchDescriptor<BoardRecord>())) ?? []
        let visible = includeArchived ? boards : boards.filter { !$0.archived }
        return visible.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func boardOverviews(includeArchived: Bool = false) -> [BoardOverview] {
        fetchBoards(includeArchived: includeArchived).map { board in
            let lists = fetchLists(boardID: board.id)
            let counts = lists.map { list in
                (role: list.role, count: fetchCards(listID: list.id).count)
            }
            let tallied = BoardOverview.tally(counts)
            let nextTitle = lists
                .filter { $0.role == .inProgress }
                .flatMap { fetchCards(listID: $0.id) }
                .first?.title
                ?? lists.filter { $0.role == .todo }.flatMap { fetchCards(listID: $0.id) }.first?.title
            return BoardOverview(
                id: board.id,
                name: board.name,
                summary: board.summary,
                pinned: board.pinned,
                archived: board.archived,
                spentHours: board.spentHours,
                todo: tallied.todo,
                inProgress: tallied.inProgress,
                done: tallied.done,
                nextTitle: nextTitle
            )
        }
    }

    func upcomingWork(limit: Int = 3) -> [WorkItem] {
        let boards = fetchBoards()
        var items: [WorkItem] = []
        func append(from roles: [ListRole]) {
            guard items.count < limit else { return }
            for board in boards {
                for list in fetchLists(boardID: board.id) where roles.contains(list.role) {
                    for card in fetchCards(listID: list.id) {
                        if items.contains(where: { $0.id == card.id }) { continue }
                        items.append(WorkItem(id: card.id, title: card.title, boardID: board.id, boardName: board.name))
                        if items.count >= limit { return }
                    }
                }
            }
        }
        append(from: [.inProgress])
        append(from: [.todo, .custom])
        return items
    }

    func fetchBoard(_ id: String) -> BoardRecord? {
        fetchBoards(includeArchived: true).first { $0.id == id }
    }

    func fetchAllLists() -> [ListRecord] {
        let lists = (try? container.mainContext.fetch(FetchDescriptor<ListRecord>())) ?? []
        return lists.sorted { $0.position < $1.position }
    }

    func fetchLists(boardID: String?) -> [ListRecord] {
        fetchAllLists().filter { boardID == nil || $0.boardID == boardID }
    }

    func fetchCards(listID: String) -> [CardRecord] {
        fetchAllCards().filter { $0.listID == listID }.sorted { $0.position < $1.position }
    }

    func fetchAllCards() -> [CardRecord] {
        (try? container.mainContext.fetch(FetchDescriptor<CardRecord>())) ?? []
    }

    func fetchCard(_ id: String) -> CardRecord? {
        fetchAllCards().first { $0.id == id }
    }

    func fetchSessions() -> [SessionRecord] {
        let sessions = (try? container.mainContext.fetch(FetchDescriptor<SessionRecord>())) ?? []
        return sessions.sorted { $0.startTime > $1.startTime }
    }

    func facts() -> [SessionFact] {
        fetchSessions().map { session in
            SessionFact(
                id: session.id,
                start: session.startTime,
                seconds: session.spentSeconds,
                boardID: session.boardID,
                rotten: session.isRotten,
                counts: session.countsAsPomodoro,
                efficiency: session.efficiency,
                primaryApp: session.primaryApp,
                apps: JSONBox.apps(session.appsJSON),
                titles: JSONBox.titles(session.titlesJSON)
            )
        }
    }

    func cardFacts() -> [CardFact] {
        let doneIDs = Set(fetchAllLists().filter { $0.role == .done }.map(\.id))
        return fetchAllCards().map { CardFact(isDone: doneIDs.contains($0.listID)) }
    }

    private func handle(_ event: ClockEvent) async {
        switch event {
        case .none:
            return
        case .breakFinished:
            notify(String(localized: "Break finished"), body: String(localized: "Focus is ready."))
            finishPrompt = FinishPrompt(
                id: UUID().uuidString,
                heading: String(localized: "Break finished"),
                nextPhase: .focus
            )
        case let .focusFinished(elapsed, rotten, counts, sessionID):
            await recordFocus(elapsed: elapsed, rotten: rotten, counts: counts, sessionID: sessionID)
        }
    }

    private func recordFocus(elapsed: TimeInterval, rotten: Bool, counts: Bool, sessionID: String?) async {
        guard elapsed >= 30, let sessionID else { return }
        let samples = (try? await activity.samples(sessionID: sessionID)) ?? []
        let sliced = ActivityLog.slices(from: samples)
        let ratio = Analytics.efficiency(
            samples: samples.map { ($0.appName, $0.windowTitle) },
            rules: settings.distractionRules
        )
        let record = SessionRecord(
            id: sessionID,
            startTime: Date().addingTimeInterval(-elapsed),
            spentSeconds: elapsed,
            switchTimes: sliced.switches,
            boardID: clock.boardID,
            isRotten: rotten,
            countsAsPomodoro: counts,
            efficiency: ratio,
            primaryApp: sliced.primary,
            appsJSON: JSONBox.apps(sliced.apps),
            titlesJSON: JSONBox.titles(sliced.titles)
        )
        container.mainContext.insert(record)
        if let boardID = clock.boardID {
            attach(session: record, hours: elapsed / 3600, boardID: boardID, cardID: clock.cardID)
        }
        saveContext()
        let suggestion = clock.boardID == nil ? suggestedBoard(primaryApp: sliced.primary) : nil
        notify(
            rotten ? String(localized: "Focus saved as incomplete") : String(localized: "Focus finished"),
            body: String(localized: "Break is ready.")
        )
        finishPrompt = FinishPrompt(
            id: sessionID,
            heading: rotten ? String(localized: "Focus saved as incomplete") : String(localized: "Focus finished"),
            sessionID: sessionID,
            suggestedBoardID: suggestion?.id,
            suggestedBoardName: suggestion?.name,
            nextPhase: clock.phase
        )
    }

    private func attach(session: SessionRecord, hours: Double, boardID: String, cardID: String?) {
        guard let board = fetchBoard(boardID) else { return }
        var related = JSONBox.strings(board.relatedSessionIDsJSON)
        if !related.contains(session.id) { related.append(session.id) }
        board.relatedSessionIDsJSON = JSONBox.strings(related)
        board.spentHours += hours
        guard let cardID, let card = fetchCard(cardID), self.boardID(for: card) == boardID else { return }
        var ids = JSONBox.strings(card.sessionIDsJSON)
        if !ids.contains(session.id) {
            ids.append(session.id)
            card.sessionIDsJSON = JSONBox.strings(ids)
            card.actualHours += hours
        }
    }

    private func suggestedBoard(primaryApp: String?) -> BoardRecord? {
        guard settings.suggestBoard, let primaryApp else { return nil }
        let history = fetchSessions().compactMap { session -> (String, String)? in
            guard let boardID = session.boardID, let app = session.primaryApp else { return nil }
            return (boardID, app)
        }
        guard let id = Analytics.suggestBoard(appName: primaryApp, history: history) else { return nil }
        guard let board = fetchBoard(id), !board.archived else { return nil }
        return board
    }

    private func notify(_ title: String, body: String) {
        Task {
            let allowed = await SessionNotifier.deliver(
                enabled: settings.notificationsEnabled,
                title: title,
                body: body,
                playSound: settings.soundEnabled
            )
            if !allowed, settings.soundEnabled {
                NSSound(named: NSSound.Name("Glass"))?.play()
            }
        }
    }

    private func startSampling() {
        stopSampling()
        guard clock.phase == .focus, clock.runState == .running, let sessionID = clock.activeSessionID else { return }
        sampleTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.capture(sessionID: sessionID)
                let interval = self?.settings.monitorInterval ?? 2
                try? await Task.sleep(for: .seconds(max(1, interval)))
            }
        }
    }

    private func stopSampling() {
        sampleTask?.cancel()
        sampleTask = nil
    }

    private func capture(sessionID: String) async {
        guard clock.activeSessionID == sessionID, clock.runState == .running else { return }
        guard let snapshot = FrontmostProbe.capture() else { return }
        try? await activity.append(
            sessionID: sessionID,
            at: .now,
            app: snapshot.appName,
            title: snapshot.windowTitle,
            bundleID: snapshot.bundleID
        )
    }

    private func saveContext() {
        do {
            try container.mainContext.save()
            revision += 1
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
