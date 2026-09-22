import Foundation

struct ImportBundle: Equatable, Sendable {
    var sessions: [ImportedSession] = []
    var cards: [ImportedCard] = []
    var lists: [ImportedList] = []
    var boards: [ImportedBoard] = []
    var moves: [ImportedMove] = []
    var focusMinutes: Int?
    var shortBreakMinutes: Int?
    var longBreakMinutes: Int?
    var longBreakInterval: Int?
    var rules: [DistractionRule] = []

    var isEmpty: Bool {
        sessions.isEmpty && cards.isEmpty && boards.isEmpty && lists.isEmpty
    }
}

struct ImportedSession: Equatable, Sendable, Identifiable {
    var id: String
    var start: Date
    var hours: Double
    var switchTimes: Int
    var boardID: String?
    var rotten: Bool
    var efficiency: Double?
    var primaryApp: String?
    var apps: [AppSlice]
    var titles: [TitleSlice]
}

struct ImportedCard: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var content: String
    var estimated: Double
    var actual: Double
    var sessionIDs: [String]
}

struct ImportedList: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var cardIDs: [String]
}

struct ImportedBoard: Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var summary: String
    var spentHours: Double
    var listIDs: [String]
    var focusedListID: String
    var doneListID: String
    var relatedSessionIDs: [String]
    var pinned: Bool
    var archived: Bool
}

struct ImportedMove: Equatable, Sendable {
    var fromListID: String
    var toListID: String
    var cardID: String
    var time: Date
}

enum DataMerger {
    static func merge(existing: ImportBundle, incoming: ImportBundle) -> ImportBundle {
        var result = existing
        let sessionIDs = Set(existing.sessions.map(\.id))
        let cardIDs = Set(existing.cards.map(\.id))
        let listIDs = Set(existing.lists.map(\.id))
        let boardIDs = Set(existing.boards.map(\.id))
        result.sessions.append(contentsOf: incoming.sessions.filter { !sessionIDs.contains($0.id) })
        result.cards.append(contentsOf: incoming.cards.filter { !cardIDs.contains($0.id) })
        result.lists.append(contentsOf: incoming.lists.filter { !listIDs.contains($0.id) })
        result.boards.append(contentsOf: incoming.boards.filter { !boardIDs.contains($0.id) })
        result.moves.append(contentsOf: incoming.moves)
        if result.focusMinutes == nil { result.focusMinutes = incoming.focusMinutes }
        if result.shortBreakMinutes == nil { result.shortBreakMinutes = incoming.shortBreakMinutes }
        if result.longBreakMinutes == nil { result.longBreakMinutes = incoming.longBreakMinutes }
        if result.longBreakInterval == nil { result.longBreakInterval = incoming.longBreakInterval }
        if result.rules.isEmpty { result.rules = incoming.rules }
        return result
    }
}

enum LegacyDecoder {
    static func bundle(fromJSON data: Data) -> ImportBundle? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard object["records"] != nil, object["cards"] != nil, object["lists"] != nil, object["boards"] != nil else {
            return nil
        }
        return bundle(from: object)
    }

    static func bundle(in directory: URL, fileManager: FileManager = .default) -> ImportBundle? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        var bundle = ImportBundle()
        bundle.sessions = documents(directory.appending(path: "session.nedb")).compactMap(session)
        bundle.cards = documents(directory.appending(path: "cards.nedb")).compactMap(card)
        bundle.lists = documents(directory.appending(path: "lists.nedb")).compactMap(list)
        bundle.boards = documents(directory.appending(path: "kanban.nedb")).compactMap(board)
        bundle.moves = documents(directory.appending(path: "moveCard.nedb")).compactMap(move)
        if let setting = documents(directory.appending(path: "setting.nedb")).first(where: { ($0["name"] as? String) == "setting" }) {
            apply(setting: setting, to: &bundle)
        }
        return bundle
    }

    static func bundle(from object: [String: Any]) -> ImportBundle {
        var bundle = ImportBundle()
        bundle.sessions = array(object["records"]).compactMap(session)
        bundle.cards = dictionary(object["cards"]).values.compactMap(card)
        bundle.lists = dictionary(object["lists"]).values.compactMap(list)
        bundle.boards = dictionary(object["boards"]).values.compactMap(board)
        bundle.moves = array(object["move"]).compactMap(move)
        return bundle
    }

    static func exportObject(from bundle: ImportBundle) -> [String: Any] {
        [
            "records": bundle.sessions.map(exportSession),
            "cards": Dictionary(uniqueKeysWithValues: bundle.cards.map { ($0.id, exportCard($0)) }),
            "lists": Dictionary(uniqueKeysWithValues: bundle.lists.map { ($0.id, exportList($0)) }),
            "boards": Dictionary(uniqueKeysWithValues: bundle.boards.map { ($0.id, exportBoard($0)) }),
            "move": bundle.moves.map { move in
                [
                    "fromListId": move.fromListID,
                    "toListId": move.toListID,
                    "cardId": move.cardID,
                    "time": move.time.timeIntervalSince1970 * 1000
                ]
            }
        ]
    }

    private static func documents(_ url: URL) -> [[String: Any]] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return object
        }
    }

    private static func array(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func dictionary(_ value: Any?) -> [String: [String: Any]] {
        value as? [String: [String: Any]] ?? [:]
    }

    private static func identifier(_ value: Any?) -> String? {
        switch value {
        case let string as String where !string.isEmpty:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let object as [String: Any]:
            return object["$oid"] as? String
        default:
            return nil
        }
    }

    private static func date(_ value: Any?) -> Date? {
        let number: Double?
        switch value {
        case let double as Double: number = double
        case let int as Int: number = Double(int)
        case let boxed as NSNumber: number = boxed.doubleValue
        default: number = nil
        }
        guard let number else { return nil }
        if number > 100_000_000_000 { return Date(timeIntervalSince1970: number / 1000) }
        return Date(timeIntervalSince1970: number)
    }

    private static func session(_ object: [String: Any]) -> ImportedSession? {
        guard let id = identifier(object["_id"]) else { return nil }
        let parsed = apps(object["apps"])
        return ImportedSession(
            id: id,
            start: date(object["startTime"]) ?? .now,
            hours: object["spentTimeInHour"] as? Double ?? (object["spentTimeInHour"] as? NSNumber)?.doubleValue ?? 0,
            switchTimes: object["switchTimes"] as? Int ?? (object["switchTimes"] as? NSNumber)?.intValue ?? 0,
            boardID: object["boardId"] as? String,
            rotten: object["isRotten"] as? Bool ?? false,
            efficiency: object["efficiency"] as? Double ?? (object["efficiency"] as? NSNumber)?.doubleValue,
            primaryApp: parsed.primary,
            apps: parsed.apps,
            titles: parsed.titles
        )
    }

    private static func apps(_ value: Any?) -> (apps: [AppSlice], titles: [TitleSlice], primary: String?) {
        guard let map = value as? [String: [String: Any]] else { return ([], [], nil) }
        var slices: [AppSlice] = []
        var titles: [TitleSlice] = []
        for (name, info) in map {
            let hours = info["spentTimeInHour"] as? Double ?? (info["spentTimeInHour"] as? NSNumber)?.doubleValue ?? 0
            slices.append(AppSlice(name: name, seconds: hours * 3600))
            if let titleMap = info["titleSpentTime"] as? [String: [String: Any]] {
                let weights = titleMap.map { key, meta -> (String, Double) in
                    let weight = meta["normalizedWeight"] as? Double ?? (meta["normalizedWeight"] as? NSNumber)?.doubleValue ?? 0
                    let occurrence = meta["occurrence"] as? Double ?? (meta["occurrence"] as? NSNumber)?.doubleValue ?? 0
                    return (key, weight > 0 ? weight : occurrence)
                }
                let total = weights.reduce(0) { $0 + $1.1 }
                for item in weights where !item.0.isEmpty {
                    let share = total > 0 ? item.1 / total : 0
                    titles.append(TitleSlice(title: item.0, seconds: hours * 3600 * share))
                }
            }
        }
        let primary = slices.max { $0.seconds < $1.seconds }?.name
        return (slices, titles, primary)
    }

    private static func card(_ object: [String: Any]) -> ImportedCard? {
        guard let id = identifier(object["_id"]) else { return nil }
        let spent = object["spentTimeInHour"] as? [String: Any] ?? [:]
        return ImportedCard(
            id: id,
            title: object["title"] as? String ?? "",
            content: object["content"] as? String ?? "",
            estimated: spent["estimated"] as? Double ?? (spent["estimated"] as? NSNumber)?.doubleValue ?? 0,
            actual: spent["actual"] as? Double ?? (spent["actual"] as? NSNumber)?.doubleValue ?? 0,
            sessionIDs: object["sessionIds"] as? [String] ?? []
        )
    }

    private static func list(_ object: [String: Any]) -> ImportedList? {
        guard let id = identifier(object["_id"]) else { return nil }
        return ImportedList(
            id: id,
            title: object["title"] as? String ?? "",
            cardIDs: object["cards"] as? [String] ?? []
        )
    }

    private static func board(_ object: [String: Any]) -> ImportedBoard? {
        guard let id = identifier(object["_id"]) else { return nil }
        return ImportedBoard(
            id: id,
            name: object["name"] as? String ?? "",
            summary: object["description"] as? String ?? "",
            spentHours: object["spentHours"] as? Double ?? (object["spentHours"] as? NSNumber)?.doubleValue ?? 0,
            listIDs: object["lists"] as? [String] ?? [],
            focusedListID: object["focusedList"] as? String ?? "",
            doneListID: object["doneList"] as? String ?? "",
            relatedSessionIDs: object["relatedSessions"] as? [String] ?? [],
            pinned: object["pin"] as? Bool ?? false,
            archived: object["archived"] as? Bool ?? false
        )
    }

    private static func move(_ object: [String: Any]) -> ImportedMove? {
        guard let card = object["cardId"] as? String,
              let from = object["fromListId"] as? String,
              let to = object["toListId"] as? String else { return nil }
        return ImportedMove(fromListID: from, toListID: to, cardID: card, time: date(object["time"]) ?? .now)
    }

    private static func apply(setting: [String: Any], to bundle: inout ImportBundle) {
        if let seconds = number(setting["focusDuration"]), seconds > 0 {
            bundle.focusMinutes = Int(seconds / 60)
        }
        if let seconds = number(setting["restDuration"]), seconds > 0 {
            bundle.shortBreakMinutes = Int(seconds / 60)
        }
        if let seconds = number(setting["longBreakDuration"]), seconds > 0 {
            bundle.longBreakMinutes = Int(seconds / 60)
        }
        if let interval = number(setting["longBreakInterval"]), interval > 0 {
            bundle.longBreakInterval = Int(interval)
        }
        if let rows = setting["distractingList"] as? [[String: Any]] {
            bundle.rules = rows.compactMap { row in
                let app = row["app"] as? String ?? ""
                let title = row["title"] as? String ?? ""
                guard !app.isEmpty || !title.isEmpty else { return nil }
                return DistractionRule(id: UUID().uuidString, app: app, title: title)
            }
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let double as Double: double
        case let int as Int: Double(int)
        case let boxed as NSNumber: boxed.doubleValue
        default: nil
        }
    }

    private static func exportSession(_ session: ImportedSession) -> [String: Any] {
        var apps: [String: Any] = [:]
        for app in session.apps {
            let hours = app.seconds / 3600
            var titles: [String: Any] = [:]
            let related = session.titles
            let total = related.reduce(0) { $0 + $1.seconds }
            for (index, title) in related.enumerated() {
                let weight = total > 0 ? title.seconds / total : 0
                titles[title.title] = ["occurrence": 1, "normalizedWeight": weight, "index": index]
            }
            apps[app.name] = [
                "appName": app.name,
                "spentTimeInHour": hours,
                "titleSpentTime": titles
            ]
        }
        var object: [String: Any] = [
            "_id": session.id,
            "apps": apps,
            "spentTimeInHour": session.hours,
            "switchTimes": session.switchTimes,
            "startTime": session.start.timeIntervalSince1970 * 1000,
            "isRotten": session.rotten
        ]
        if let boardID = session.boardID { object["boardId"] = boardID }
        if let efficiency = session.efficiency { object["efficiency"] = efficiency }
        return object
    }

    private static func exportCard(_ card: ImportedCard) -> [String: Any] {
        [
            "_id": card.id,
            "title": card.title,
            "content": card.content,
            "sessionIds": card.sessionIDs,
            "spentTimeInHour": ["estimated": card.estimated, "actual": card.actual]
        ]
    }

    private static func exportList(_ list: ImportedList) -> [String: Any] {
        ["_id": list.id, "title": list.title, "cards": list.cardIDs]
    }

    private static func exportBoard(_ board: ImportedBoard) -> [String: Any] {
        [
            "_id": board.id,
            "name": board.name,
            "description": board.summary,
            "spentHours": board.spentHours,
            "lists": board.listIDs,
            "focusedList": board.focusedListID,
            "doneList": board.doneListID,
            "relatedSessions": board.relatedSessionIDs,
            "pin": board.pinned,
            "archived": board.archived
        ]
    }
}
