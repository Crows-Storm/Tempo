import Foundation

enum DurationMarks {
    static let focus = [15, 20, 25, 30, 45, 50, 60, 90]
    static let shortBreak = [3, 5, 8, 10, 15]
    static let longBreak = [10, 15, 20, 25, 30]
    static let sessions = [2, 3, 4, 5, 6, 8]

    static func nearest(_ value: Int, in marks: [Int]) -> Int {
        guard let first = marks.first else { return value }
        return marks.min { abs($0 - value) < abs($1 - value) } ?? first
    }

    static func index(of value: Int, in marks: [Int]) -> Int {
        let snapped = nearest(value, in: marks)
        return marks.firstIndex(of: snapped) ?? 0
    }
}
