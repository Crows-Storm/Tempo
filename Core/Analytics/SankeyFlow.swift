import Foundation

struct SankeyNode: Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    var column: Int
    var seconds: Double
}

struct SankeyLink: Equatable, Sendable, Identifiable {
    var id: String
    var source: String
    var target: String
    var seconds: Double
    var distracted: Bool
}

struct SankeyDiagram: Equatable, Sendable {
    var nodes: [SankeyNode]
    var links: [SankeyLink]

    static let empty = SankeyDiagram(nodes: [], links: [])
}

enum SankeyFlow {
    static let focusedID = "outcome-focused"
    static let distractedID = "outcome-distracted"

    static func make(
        samples: [ActivitySample],
        rules: [DistractionRule],
        fallbackInterval: TimeInterval
    ) -> SankeyDiagram {
        guard samples.count > 1 || (samples.count == 1 && fallbackInterval > 0) else { return .empty }
        var appSeconds: [String: Double] = [:]
        var titleSeconds: [String: Double] = [:]
        var appToTitle: [String: Double] = [:]
        var titleToFocus: [String: Double] = [:]
        var titleToDistract: [String: Double] = [:]

        let sorted = samples
            .filter { !SystemChrome.isIgnored(appName: $0.appName, bundleID: $0.bundleID) }
            .sorted { $0.capturedAt < $1.capturedAt }
        for (index, sample) in sorted.enumerated() {
            let next = index + 1 < sorted.count ? sorted[index + 1].capturedAt : nil
            let seconds = next.map { max(0.5, $0.timeIntervalSince(sample.capturedAt)) } ?? fallbackInterval
            let app = sample.appName.isEmpty ? String(localized: "Unknown") : sample.appName
            let title = sample.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let distracted = rules.contains { $0.matches(appName: sample.appName, title: sample.windowTitle) }
            appSeconds[app, default: 0] += seconds
            accumulate(
                app: app,
                title: title,
                seconds: seconds,
                distracted: distracted,
                titleSeconds: &titleSeconds,
                appToTitle: &appToTitle,
                titleToFocus: &titleToFocus,
                titleToDistract: &titleToDistract
            )
        }

        return assemble(
            appSeconds: appSeconds,
            titleSeconds: titleSeconds,
            appToTitle: appToTitle,
            titleToFocus: titleToFocus,
            titleToDistract: titleToDistract
        )
    }

    static func make(intervals: [FocusInterval]) -> SankeyDiagram {
        guard !intervals.isEmpty else { return .empty }
        var appSeconds: [String: Double] = [:]
        var titleSeconds: [String: Double] = [:]
        var appToTitle: [String: Double] = [:]
        var titleToFocus: [String: Double] = [:]
        var titleToDistract: [String: Double] = [:]
        for interval in intervals where !SystemChrome.isIgnored(appName: interval.app) {
            let app = interval.app.isEmpty ? String(localized: "Unknown") : interval.app
            let title = interval.title.trimmingCharacters(in: .whitespacesAndNewlines)
            appSeconds[app, default: 0] += interval.duration
            accumulate(
                app: app,
                title: title,
                seconds: interval.duration,
                distracted: interval.distracted,
                titleSeconds: &titleSeconds,
                appToTitle: &appToTitle,
                titleToFocus: &titleToFocus,
                titleToDistract: &titleToDistract
            )
        }
        return assemble(
            appSeconds: appSeconds,
            titleSeconds: titleSeconds,
            appToTitle: appToTitle,
            titleToFocus: titleToFocus,
            titleToDistract: titleToDistract
        )
    }

    static func compacted(_ diagram: SankeyDiagram, maxTitles: Int = 8) -> SankeyDiagram {
        let titles = diagram.nodes.filter { $0.column == 1 }.sorted { $0.seconds > $1.seconds }
        guard titles.count > maxTitles else { return diagram }
        let keep = Array(titles.prefix(maxTitles - 1))
        let keepIDs = Set(keep.map(\.id))
        let rest = titles.filter { !keepIDs.contains($0.id) }
        let restIDs = Set(rest.map(\.id))
        let otherID = "title-other"
        var nodes = diagram.nodes.filter { $0.column != 1 || keepIDs.contains($0.id) }
        nodes.append(
            SankeyNode(
                id: otherID,
                label: String(localized: "Other"),
                column: 1,
                seconds: rest.reduce(0) { $0 + $1.seconds }
            )
        )
        var merged: [String: SankeyLink] = [:]
        for link in diagram.links {
            var next = link
            if restIDs.contains(link.source) { next.source = otherID }
            if restIDs.contains(link.target) { next.target = otherID }
            let key = "\(next.source)|\(next.target)|\(next.distracted)"
            if var existing = merged[key] {
                existing.seconds += next.seconds
                merged[key] = existing
            } else {
                next.id = key
                merged[key] = next
            }
        }
        return SankeyDiagram(
            nodes: nodes.filter { $0.seconds > 0 }.sorted {
                if $0.column != $1.column { return $0.column < $1.column }
                return $0.seconds > $1.seconds
            },
            links: Array(merged.values).filter { $0.seconds > 0 }
        )
    }

    private static func accumulate(
        app: String,
        title: String,
        seconds: Double,
        distracted: Bool,
        titleSeconds: inout [String: Double],
        appToTitle: inout [String: Double],
        titleToFocus: inout [String: Double],
        titleToDistract: inout [String: Double]
    ) {
        let resolved = title.isEmpty ? String(localized: "Untitled") : title
        titleSeconds[resolved, default: 0] += seconds
        appToTitle["\(app)\u{1f}\(resolved)", default: 0] += seconds
        if distracted {
            titleToDistract[resolved, default: 0] += seconds
        } else {
            titleToFocus[resolved, default: 0] += seconds
        }
    }

    private static func assemble(
        appSeconds: [String: Double],
        titleSeconds: [String: Double],
        appToTitle: [String: Double],
        titleToFocus: [String: Double],
        titleToDistract: [String: Double]
    ) -> SankeyDiagram {
        var nodes: [SankeyNode] = appSeconds.keys.sorted().map {
            SankeyNode(id: "app-\($0)", label: $0, column: 0, seconds: appSeconds[$0] ?? 0)
        }
        nodes += titleSeconds.keys.sorted().map {
            SankeyNode(id: "title-\($0)", label: $0, column: 1, seconds: titleSeconds[$0] ?? 0)
        }
        let focused = titleToFocus.values.reduce(0, +)
        let distracted = titleToDistract.values.reduce(0, +)
        if focused > 0 {
            nodes.append(SankeyNode(id: focusedID, label: String(localized: "Focused"), column: 2, seconds: focused))
        }
        if distracted > 0 {
            nodes.append(SankeyNode(id: distractedID, label: String(localized: "Distracted"), column: 2, seconds: distracted))
        }
        var links: [SankeyLink] = []
        for (key, seconds) in appToTitle {
            let parts = key.split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let app = String(parts[0])
            let title = String(parts[1])
            links.append(SankeyLink(id: "a-\(key)", source: "app-\(app)", target: "title-\(title)", seconds: seconds, distracted: false))
        }
        for (title, seconds) in titleToFocus {
            links.append(SankeyLink(id: "f-\(title)", source: "title-\(title)", target: focusedID, seconds: seconds, distracted: false))
        }
        for (title, seconds) in titleToDistract {
            links.append(SankeyLink(id: "d-\(title)", source: "title-\(title)", target: distractedID, seconds: seconds, distracted: true))
        }
        return SankeyDiagram(
            nodes: nodes.filter { $0.seconds > 0 }.sorted {
                if $0.column != $1.column { return $0.column < $1.column }
                return $0.seconds > $1.seconds
            },
            links: links.filter { $0.seconds > 0 }
        )
    }
}
