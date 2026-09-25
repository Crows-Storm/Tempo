import Foundation

struct FocusInterval: Identifiable, Equatable, Sendable {
    var id: String
    var start: TimeInterval
    var duration: TimeInterval
    var app: String
    var title: String
    var distracted: Bool

    var end: TimeInterval { start + duration }
}

enum FocusLane {
    static func make(
        samples: [ActivitySample],
        session: SessionFact,
        rules: [DistractionRule],
        fallback: TimeInterval
    ) -> [FocusInterval] {
        let fromSamples = fromActivity(
            samples,
            rules: rules,
            fallback: max(1, fallback),
            length: max(1, session.seconds)
        )
        if !fromSamples.isEmpty { return fromSamples }
        return fromApps(session)
    }

    static func concatenate(_ parts: [(session: SessionFact, intervals: [FocusInterval])]) -> (intervals: [FocusInterval], length: TimeInterval) {
        let ordered = parts.sorted { $0.session.start < $1.session.start }
        var offset: TimeInterval = 0
        var result: [FocusInterval] = []
        for part in ordered {
            for interval in part.intervals {
                var next = interval
                next.id = "\(part.session.id)-\(interval.id)"
                next.start += offset
                result.append(next)
            }
            offset += max(1, part.session.seconds)
        }
        return (result, offset)
    }

    static func focusedSeconds(_ intervals: [FocusInterval]) -> TimeInterval {
        intervals.filter { !$0.distracted }.reduce(0) { $0 + $1.duration }
    }

    static func distractedSeconds(_ intervals: [FocusInterval]) -> TimeInterval {
        intervals.filter(\.distracted).reduce(0) { $0 + $1.duration }
    }

    private static func fromActivity(
        _ samples: [ActivitySample],
        rules: [DistractionRule],
        fallback: TimeInterval,
        length: TimeInterval
    ) -> [FocusInterval] {
        let sorted = samples
            .filter { !SystemChrome.isIgnored(appName: $0.appName, bundleID: $0.bundleID) }
            .sorted { $0.capturedAt < $1.capturedAt }
        guard let origin = sorted.first?.capturedAt else { return [] }
        var pieces: [FocusInterval] = []
        for (index, sample) in sorted.enumerated() {
            let start = min(length, max(0, sample.capturedAt.timeIntervalSince(origin)))
            let end: TimeInterval
            if index + 1 < sorted.count {
                end = min(length, max(start, sorted[index + 1].capturedAt.timeIntervalSince(origin)))
            } else {
                end = max(start + 0.5, length)
            }
            let duration = max(0.5, end - start)
            let app = sample.appName.isEmpty ? String(localized: "Unknown") : sample.appName
            let title = sample.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            pieces.append(
                FocusInterval(
                    id: "\(index)-\(app)",
                    start: start,
                    duration: duration,
                    app: app,
                    title: title,
                    distracted: rules.contains { $0.matches(appName: sample.appName, title: sample.windowTitle) }
                )
            )
        }
        return merge(pieces)
    }

    private static func fromApps(_ session: SessionFact) -> [FocusInterval] {
        let apps = session.apps.filter { $0.seconds > 0 && !SystemChrome.isIgnored(appName: $0.name) }
        let length = max(1, session.seconds)
        guard !apps.isEmpty else {
            return [
                FocusInterval(
                    id: "focus",
                    start: 0,
                    duration: length,
                    app: session.primaryApp ?? String(localized: "Focus"),
                    title: "",
                    distracted: false
                )
            ]
        }
        let total = apps.reduce(0) { $0 + $1.seconds }
        let scale = total > 0 ? length / total : 1
        var start: TimeInterval = 0
        var pieces: [FocusInterval] = []
        for (index, app) in apps.enumerated() {
            let duration = max(0.5, app.seconds * scale)
            pieces.append(
                FocusInterval(
                    id: "app-\(index)-\(app.name)",
                    start: start,
                    duration: duration,
                    app: app.name,
                    title: "",
                    distracted: false
                )
            )
            start += duration
        }
        return pieces
    }

    private static func merge(_ pieces: [FocusInterval]) -> [FocusInterval] {
        guard var current = pieces.first else { return [] }
        var result: [FocusInterval] = []
        for piece in pieces.dropFirst() {
            if piece.app == current.app, piece.distracted == current.distracted {
                current.duration += piece.duration
            } else {
                result.append(current)
                current = piece
            }
        }
        result.append(current)
        return result
    }
}
