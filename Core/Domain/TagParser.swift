import Foundation

enum TagParser {
    static func tags(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "#[\\p{L}\\p{N}_-]+") else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range).lowercased()
        }
    }

    static func matches(query: String, title: String, notes: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.hasPrefix("#") {
            let tags = Set(self.tags(in: title) + self.tags(in: notes))
            return tags.contains(trimmed.lowercased())
        }
        return title.localizedStandardContains(trimmed) || notes.localizedStandardContains(trimmed)
    }
}

enum ListRole: String, Codable, Sendable {
    case todo
    case inProgress
    case done
    case custom

    var canDelete: Bool { self == .custom }
    var canRename: Bool { self == .custom }
}
