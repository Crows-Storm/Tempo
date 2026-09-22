import CoreGraphics
import Foundation

enum WindowTitle {
    static let cacheTTL: TimeInterval = 0.75

    static func string(from value: Any?) -> String {
        let raw: String
        switch value {
        case let text as String:
            raw = text
        case let text as NSAttributedString:
            raw = text.string
        default:
            raw = ""
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func documentName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let url = URL(string: trimmed), url.scheme != nil {
            let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
            return name.isEmpty ? trimmed : name
        }
        if trimmed.contains("/") {
            return URL(fileURLWithPath: trimmed).lastPathComponent
        }
        return trimmed
    }

    static func fromWindowList(_ windows: [[String: Any]], pid: Int) -> String {
        var bestName = ""
        var bestArea = -1.0
        for window in windows {
            guard intValue(window[kCGWindowOwnerPID as String]) == pid else { continue }
            guard intValue(window[kCGWindowLayer as String]) == 0 else { continue }
            let name = string(from: window[kCGWindowName as String])
            guard !name.isEmpty else { continue }
            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let area = doubleValue(bounds["Width"]) * doubleValue(bounds["Height"])
            if area > bestArea {
                bestArea = area
                bestName = name
            }
        }
        return bestName
    }

    static func shouldReuseCache(
        pid: pid_t,
        cachedPID: pid_t,
        cachedTitle: String,
        cachedAt: Date,
        now: Date = .now
    ) -> Bool {
        pid == cachedPID && !cachedTitle.isEmpty && now.timeIntervalSince(cachedAt) < cacheTTL
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let number as Int: number
        case let number as Int32: Int(number)
        case let number as NSNumber: number.intValue
        default: 0
        }
    }

    private static func doubleValue(_ value: Any?) -> Double {
        switch value {
        case let number as Double: number
        case let number as Int: Double(number)
        case let number as NSNumber: number.doubleValue
        default: 0
        }
    }
}
