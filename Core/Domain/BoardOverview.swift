import Foundation

struct BoardOverview: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var summary: String
    var pinned: Bool
    var archived: Bool
    var spentHours: Double
    var todo: Int
    var inProgress: Int
    var done: Int
    var nextTitle: String?

    var total: Int { todo + inProgress + done }

    var canArchive: Bool {
        !archived && total > 0 && todo == 0 && inProgress == 0
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    static func tally(_ lists: [(role: ListRole, count: Int)]) -> (todo: Int, inProgress: Int, done: Int) {
        var todo = 0
        var inProgress = 0
        var done = 0
        for item in lists {
            switch item.role {
            case .todo, .custom:
                todo += item.count
            case .inProgress:
                inProgress += item.count
            case .done:
                done += item.count
            }
        }
        return (todo, inProgress, done)
    }
}

struct WorkItem: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var boardID: String
    var boardName: String
}
