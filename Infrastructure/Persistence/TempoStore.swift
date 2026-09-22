import Foundation
import SwiftData

struct TempoStack {
    let container: ModelContainer
    let activity: ActivityLog
    let folder: URL
}

enum TempoStore {
    static func live() throws -> TempoStack {
        let folder = try supportFolder()
        let storeURL = folder.appending(path: "Tempo.store")
        let activityURL = folder.appending(path: "activity.sqlite")
        return try open(storeURL: storeURL, activityPath: activityURL.path, folder: folder)
    }

    static func memory() throws -> TempoStack {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Tempo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try open(storeURL: folder.appending(path: "Tempo.store"), activityPath: ":memory:", folder: folder)
    }

    static func supportFolder() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = base.appending(path: "Tempo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func open(storeURL: URL, activityPath: String, folder: URL) throws -> TempoStack {
        let schema = Schema([
            BoardRecord.self,
            ListRecord.self,
            CardRecord.self,
            SessionRecord.self,
            MoveRecord.self
        ])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let activity = try ActivityLog(path: activityPath)
        return TempoStack(container: container, activity: activity, folder: folder)
    }
}

enum LibraryImporter {
    static let markerName = "legacy-import.json"

    static func legacyDirectories() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: "Library/Application Support/Tempo/db"),
            home.appending(path: "Library/Preferences/PomodoroLogger/db")
        ]
    }

    static func loadExternal() -> ImportBundle {
        var combined = ImportBundle()
        for directory in legacyDirectories() {
            guard let bundle = LegacyDecoder.bundle(in: directory) else { continue }
            combined = DataMerger.merge(existing: combined, incoming: bundle)
        }
        return combined
    }

    static func markerURL(in folder: URL) -> URL {
        folder.appending(path: markerName)
    }

    @MainActor
    static func apply(_ bundle: ImportBundle, context: ModelContext, settings: inout AppSettings) throws {
        let boards = try context.fetch(FetchDescriptor<BoardRecord>())
        let lists = try context.fetch(FetchDescriptor<ListRecord>())
        let cards = try context.fetch(FetchDescriptor<CardRecord>())
        let sessions = try context.fetch(FetchDescriptor<SessionRecord>())
        let boardIDs = Set(boards.map(\.id))
        let listIDs = Set(lists.map(\.id))
        let cardIDs = Set(cards.map(\.id))
        let sessionIDs = Set(sessions.map(\.id))

        for board in bundle.boards where !boardIDs.contains(board.id) {
            context.insert(BoardRecord(
                id: board.id,
                name: board.name.isEmpty ? String(localized: "Personal") : board.name,
                summary: board.summary,
                spentHours: board.spentHours,
                focusedListID: board.focusedListID,
                doneListID: board.doneListID,
                pinned: board.pinned,
                archived: board.archived,
                relatedSessionIDsJSON: JSONBox.strings(board.relatedSessionIDs)
            ))
        }

        for list in bundle.lists where !listIDs.contains(list.id) {
            let board = bundle.boards.first { $0.listIDs.contains(list.id) }
            let index = board?.listIDs.firstIndex(of: list.id) ?? 0
            let role = role(for: list, board: board, index: index)
            context.insert(ListRecord(
                id: list.id,
                boardID: board?.id ?? "",
                title: list.title,
                roleRaw: role.rawValue,
                position: index
            ))
        }

        for card in bundle.cards where !cardIDs.contains(card.id) {
            let listID = bundle.lists.first { $0.cardIDs.contains(card.id) }?.id ?? ""
            let position = bundle.lists.first { $0.id == listID }?.cardIDs.firstIndex(of: card.id) ?? 0
            context.insert(CardRecord(
                id: card.id,
                listID: listID,
                title: card.title,
                notes: card.content,
                estimatedHours: card.estimated,
                actualHours: card.actual,
                sessionIDsJSON: JSONBox.strings(card.sessionIDs),
                position: position
            ))
        }

        for session in bundle.sessions where !sessionIDs.contains(session.id) {
            context.insert(SessionRecord(
                id: session.id,
                startTime: session.start,
                spentSeconds: session.hours * 3600,
                switchTimes: session.switchTimes,
                boardID: session.boardID,
                isRotten: session.rotten,
                countsAsPomodoro: !session.rotten && session.hours > 0,
                efficiency: session.efficiency,
                primaryApp: session.primaryApp,
                appsJSON: JSONBox.apps(session.apps),
                titlesJSON: JSONBox.titles(session.titles)
            ))
        }

        for move in bundle.moves {
            context.insert(MoveRecord(fromListID: move.fromListID, toListID: move.toListID, cardID: move.cardID, time: move.time))
        }

        if let minutes = bundle.focusMinutes { settings.focusMinutes = minutes }
        if let minutes = bundle.shortBreakMinutes { settings.shortBreakMinutes = minutes }
        if let minutes = bundle.longBreakMinutes { settings.longBreakMinutes = minutes }
        if let interval = bundle.longBreakInterval { settings.longBreakInterval = interval }
        if !bundle.rules.isEmpty { settings.distractionRules = bundle.rules }
        try context.save()
    }

    static func exportBundle(context: ModelContext) throws -> ImportBundle {
        let boards = try context.fetch(FetchDescriptor<BoardRecord>())
        let lists = try context.fetch(FetchDescriptor<ListRecord>()).sorted { $0.position < $1.position }
        let cards = try context.fetch(FetchDescriptor<CardRecord>()).sorted { $0.position < $1.position }
        let sessions = try context.fetch(FetchDescriptor<SessionRecord>())
        let moves = try context.fetch(FetchDescriptor<MoveRecord>())
        return ImportBundle(
            sessions: sessions.map { session in
                ImportedSession(
                    id: session.id,
                    start: session.startTime,
                    hours: session.spentSeconds / 3600,
                    switchTimes: session.switchTimes,
                    boardID: session.boardID,
                    rotten: session.isRotten,
                    efficiency: session.efficiency,
                    primaryApp: session.primaryApp,
                    apps: JSONBox.apps(session.appsJSON),
                    titles: JSONBox.titles(session.titlesJSON)
                )
            },
            cards: cards.map { card in
                ImportedCard(
                    id: card.id,
                    title: card.title,
                    content: card.notes,
                    estimated: card.estimatedHours,
                    actual: card.actualHours,
                    sessionIDs: JSONBox.strings(card.sessionIDsJSON)
                )
            },
            lists: lists.map { list in
                ImportedList(
                    id: list.id,
                    title: list.title,
                    cardIDs: cards.filter { $0.listID == list.id }.sorted { $0.position < $1.position }.map(\.id)
                )
            },
            boards: boards.map { board in
                ImportedBoard(
                    id: board.id,
                    name: board.name,
                    summary: board.summary,
                    spentHours: board.spentHours,
                    listIDs: lists.filter { $0.boardID == board.id }.sorted { $0.position < $1.position }.map(\.id),
                    focusedListID: board.focusedListID,
                    doneListID: board.doneListID,
                    relatedSessionIDs: JSONBox.strings(board.relatedSessionIDsJSON),
                    pinned: board.pinned,
                    archived: board.archived
                )
            },
            moves: moves.map {
                ImportedMove(fromListID: $0.fromListID, toListID: $0.toListID, cardID: $0.cardID, time: $0.time)
            }
        )
    }

    private static func role(for list: ImportedList, board: ImportedBoard?, index: Int) -> ListRole {
        if list.id == board?.focusedListID { return .inProgress }
        if list.id == board?.doneListID { return .done }
        if index == 0 { return .todo }
        let folded = list.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if folded.contains("todo") || folded.contains("to do") || folded.contains("待办") || folded.contains("やること") {
            return .todo
        }
        return .custom
    }
}
