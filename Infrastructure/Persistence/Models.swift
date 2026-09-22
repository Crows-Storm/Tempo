import Foundation
import SwiftData

@Model
final class BoardRecord {
    @Attribute(.unique) var id: String
    var name: String
    var summary: String
    var spentHours: Double
    var focusedListID: String
    var doneListID: String
    var pinned: Bool
    var archived: Bool = false
    var lastVisit: Date
    var relatedSessionIDsJSON: String

    init(
        id: String,
        name: String,
        summary: String = "",
        spentHours: Double = 0,
        focusedListID: String,
        doneListID: String,
        pinned: Bool = false,
        archived: Bool = false,
        lastVisit: Date = .now,
        relatedSessionIDsJSON: String = "[]"
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.spentHours = spentHours
        self.focusedListID = focusedListID
        self.doneListID = doneListID
        self.pinned = pinned
        self.archived = archived
        self.lastVisit = lastVisit
        self.relatedSessionIDsJSON = relatedSessionIDsJSON
    }
}

@Model
final class ListRecord {
    @Attribute(.unique) var id: String
    var boardID: String
    var title: String
    var roleRaw: String
    var position: Int

    init(id: String, boardID: String, title: String, roleRaw: String, position: Int) {
        self.id = id
        self.boardID = boardID
        self.title = title
        self.roleRaw = roleRaw
        self.position = position
    }

    var role: ListRole { ListRole(rawValue: roleRaw) ?? .custom }
}

@Model
final class CardRecord {
    @Attribute(.unique) var id: String
    var listID: String
    var title: String
    var notes: String
    var estimatedHours: Double
    var actualHours: Double
    var sessionIDsJSON: String
    var position: Int
    var createdAt: Date

    init(
        id: String,
        listID: String,
        title: String,
        notes: String = "",
        estimatedHours: Double = 0,
        actualHours: Double = 0,
        sessionIDsJSON: String = "[]",
        position: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.listID = listID
        self.title = title
        self.notes = notes
        self.estimatedHours = estimatedHours
        self.actualHours = actualHours
        self.sessionIDsJSON = sessionIDsJSON
        self.position = position
        self.createdAt = createdAt
    }
}

@Model
final class SessionRecord {
    @Attribute(.unique) var id: String
    var startTime: Date
    var spentSeconds: Double
    var switchTimes: Int
    var boardID: String?
    var isRotten: Bool
    var countsAsPomodoro: Bool
    var efficiency: Double?
    var primaryApp: String?
    var appsJSON: String
    var titlesJSON: String

    init(
        id: String,
        startTime: Date,
        spentSeconds: Double,
        switchTimes: Int = 0,
        boardID: String? = nil,
        isRotten: Bool = false,
        countsAsPomodoro: Bool = false,
        efficiency: Double? = nil,
        primaryApp: String? = nil,
        appsJSON: String = "[]",
        titlesJSON: String = "[]"
    ) {
        self.id = id
        self.startTime = startTime
        self.spentSeconds = spentSeconds
        self.switchTimes = switchTimes
        self.boardID = boardID
        self.isRotten = isRotten
        self.countsAsPomodoro = countsAsPomodoro
        self.efficiency = efficiency
        self.primaryApp = primaryApp
        self.appsJSON = appsJSON
        self.titlesJSON = titlesJSON
    }
}

@Model
final class MoveRecord {
    var fromListID: String
    var toListID: String
    var cardID: String
    var time: Date

    init(fromListID: String, toListID: String, cardID: String, time: Date) {
        self.fromListID = fromListID
        self.toListID = toListID
        self.cardID = cardID
        self.time = time
    }
}

enum JSONBox {
    static func strings(_ raw: String) -> [String] {
        decode(raw) ?? []
    }

    static func strings(_ values: [String]) -> String {
        encode(values) ?? "[]"
    }

    static func apps(_ raw: String) -> [AppSlice] {
        decode(raw) ?? []
    }

    static func apps(_ values: [AppSlice]) -> String {
        encode(values) ?? "[]"
    }

    static func titles(_ raw: String) -> [TitleSlice] {
        decode(raw) ?? []
    }

    static func titles(_ values: [TitleSlice]) -> String {
        encode(values) ?? "[]"
    }

    private static func decode<T: Decodable>(_ raw: String) -> T? {
        guard let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
