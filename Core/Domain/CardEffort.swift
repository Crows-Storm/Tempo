import Foundation

enum CardEffort {
    static func plannedPomodoros(estimatedHours: Double, focusMinutes: Int) -> Int {
        max(1, count(hours: max(0, estimatedHours), focusMinutes: focusMinutes))
    }

    static func donePomodoros(sessionIDsJSON: String, actualHours: Double, focusMinutes: Int) -> Int {
        let linked = JSONBox.strings(sessionIDsJSON).count
        if linked > 0 { return linked }
        return count(hours: max(0, actualHours), focusMinutes: focusMinutes)
    }

    static func fraction(actualHours: Double, estimatedHours: Double) -> Double {
        guard estimatedHours > 0 else { return actualHours > 0 ? 1 : 0 }
        return min(1, max(0, actualHours / estimatedHours))
    }

    static func isOverEstimate(actualHours: Double, estimatedHours: Double) -> Bool {
        estimatedHours > 0 && actualHours > estimatedHours
    }

    static func count(hours: Double, focusMinutes: Int) -> Int {
        let focus = Double(max(1, focusMinutes))
        return Int(((hours * 60) / focus).rounded())
    }
}
