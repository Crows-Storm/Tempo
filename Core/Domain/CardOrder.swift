import Foundation

enum CardOrder {
    static func inserted(_ moving: [String], into ordered: [String], before: String?) -> [String] {
        var next = ordered.filter { !moving.contains($0) }
        let payload = moving.filter { !next.contains($0) }
        if let before, let index = next.firstIndex(of: before) {
            next.insert(contentsOf: payload, at: index)
        } else {
            next.append(contentsOf: payload)
        }
        return next
    }
}
