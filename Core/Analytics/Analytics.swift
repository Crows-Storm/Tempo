import Foundation

struct AppSlice: Codable, Equatable, Sendable, Identifiable {
    var name: String
    var seconds: Double
    var id: String { name }
}

struct TitleSlice: Codable, Equatable, Sendable, Identifiable {
    var title: String
    var seconds: Double
    var id: String { title }
}

struct SessionFact: Equatable, Sendable, Identifiable {
    var id: String
    var start: Date
    var seconds: TimeInterval
    var boardID: String?
    var rotten: Bool
    var counts: Bool
    var efficiency: Double?
    var primaryApp: String?
    var apps: [AppSlice]
    var titles: [TitleSlice]
}

struct CardFact: Equatable, Sendable {
    var isDone: Bool
}

enum StatsRange: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    var id: String { rawValue }
}

struct DayPoint: Equatable, Sendable, Identifiable {
    var day: Date
    var minutes: Int
    var id: Date { day }
}

struct HeatmapDay: Equatable, Sendable, Identifiable {
    var day: Date
    var minutes: Int
    var sessions: Int
    var inRange: Bool
    var id: Date { day }

    var level: Int {
        switch minutes {
        case 0: 0
        case 1..<25: 1
        case 25..<50: 2
        case 50..<100: 3
        default: 4
        }
    }
}

struct HeatmapWeek: Equatable, Sendable, Identifiable {
    var start: Date
    var days: [HeatmapDay]
    var id: Date { start }
}

struct StatisticsSnapshot: Equatable, Sendable {
    var todayMinutes: Int
    var pomodoros: Int
    var completedCards: Int
    var totalCards: Int
    var completion: Double?
    var averageMinutes: Int?
    var streak: Int
    var points: [DayPoint]
    var apps: [AppSlice]
    var titles: [TitleSlice]
    var heatmap: [HeatmapWeek]
    var efficiency: Double?

    static let empty = StatisticsSnapshot(
        todayMinutes: 0,
        pomodoros: 0,
        completedCards: 0,
        totalCards: 0,
        completion: nil,
        averageMinutes: nil,
        streak: 0,
        points: [],
        apps: [],
        titles: [],
        heatmap: [],
        efficiency: nil
    )
}

enum Analytics {
    static func todaySeconds(sessions: [SessionFact], now: Date, calendar: Calendar) -> TimeInterval {
        sessions
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
            .reduce(0) { $0 + $1.seconds }
    }

    static func make(
        sessions: [SessionFact],
        cards: [CardFact],
        range: StatsRange,
        now: Date,
        calendar: Calendar
    ) -> StatisticsSnapshot {
        let today = calendar.startOfDay(for: now)
        let todaySeconds = Self.todaySeconds(sessions: sessions, now: now, calendar: calendar)
        let ranged = sessions.filter { inRange($0.start, range: range, now: now, calendar: calendar) }
        let full = ranged.filter(\.counts)
        let average = full.isEmpty ? nil : Int(full.reduce(0) { $0 + $1.seconds } / Double(full.count) / 60)
        let done = cards.filter(\.isDone).count
        let completion = cards.isEmpty ? nil : Double(done) / Double(cards.count)
        let efficiencies = ranged.compactMap(\.efficiency)
        let efficiency = efficiencies.isEmpty ? nil : efficiencies.reduce(0, +) / Double(efficiencies.count)
        return StatisticsSnapshot(
            todayMinutes: Int(todaySeconds / 60),
            pomodoros: full.count,
            completedCards: done,
            totalCards: cards.count,
            completion: completion,
            averageMinutes: average,
            streak: streak(sessions: sessions, today: today, calendar: calendar),
            points: points(sessions: sessions, range: range, now: now, calendar: calendar),
            apps: topApps(ranged),
            titles: topTitles(ranged),
            heatmap: heatmap(sessions: sessions, now: now, calendar: calendar),
            efficiency: efficiency
        )
    }

    static func streak(sessions: [SessionFact], today: Date, calendar: Calendar) -> Int {
        let days = Set(sessions.filter { $0.counts || $0.seconds >= 600 }.map { calendar.startOfDay(for: $0.start) })
        var cursor = today
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    static func heatmap(sessions: [SessionFact], now: Date, calendar: Calendar, weeks: Int = 53) -> [HeatmapWeek] {
        let today = calendar.startOfDay(for: now)
        let span = weeks * 7 - 1
        var start = calendar.date(byAdding: .day, value: -span, to: today) ?? today
        let weekday = calendar.component(.weekday, from: start)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        start = calendar.date(byAdding: .day, value: -delta, to: start) ?? start

        var totals: [Date: (minutes: Int, sessions: Int)] = [:]
        for session in sessions where session.seconds > 0 {
            let day = calendar.startOfDay(for: session.start)
            var current = totals[day] ?? (0, 0)
            current.minutes += Int(session.seconds / 60)
            current.sessions += 1
            totals[day] = current
        }

        var result: [HeatmapWeek] = []
        var cursor = start
        while cursor <= today || result.isEmpty {
            var days: [HeatmapDay] = []
            let weekStart = cursor
            for _ in 0..<7 {
                let value = totals[cursor] ?? (0, 0)
                days.append(HeatmapDay(
                    day: cursor,
                    minutes: cursor > today ? 0 : value.minutes,
                    sessions: cursor > today ? 0 : value.sessions,
                    inRange: cursor <= today
                ))
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            }
            result.append(HeatmapWeek(start: weekStart, days: days))
            if cursor > today && result.count >= weeks { break }
            if result.count > weeks + 2 { break }
        }
        return result
    }

    static func efficiency(samples: [(app: String, title: String)], rules: [DistractionRule]) -> Double? {
        let active = rules.filter { !$0.app.isEmpty || !$0.title.isEmpty }
        guard !samples.isEmpty, !active.isEmpty else { return nil }
        let distracted = samples.filter { sample in
            active.contains { $0.matches(appName: sample.app, title: sample.title) }
        }.count
        return 1 - Double(distracted) / Double(samples.count)
    }

    static func pomodoroTally(sessions: [SessionFact], now: Date, calendar: Calendar) -> (today: Int, week: Int, month: Int) {
        let full = sessions.filter(\.counts)
        let today = full.filter { calendar.isDate($0.start, inSameDayAs: now) }.count
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        let week = full.filter { $0.start >= weekStart }.count
        let month = full.filter { $0.start >= monthStart }.count
        return (today, week, month)
    }

    static func suggestBoard(appName: String, history: [(boardID: String, app: String)]) -> String? {
        let needle = appName.lowercased()
        guard !needle.isEmpty else { return nil }
        var scores: [String: Int] = [:]
        for item in history where item.app.lowercased() == needle {
            scores[item.boardID, default: 0] += 1
        }
        return scores.max { $0.value < $1.value }?.key
    }

    private static func inRange(_ date: Date, range: StatsRange, now: Date, calendar: Calendar) -> Bool {
        switch range {
        case .day:
            return calendar.isDate(date, inSameDayAs: now)
        case .week:
            guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return false }
            return date >= start && date <= now
        case .month:
            guard let start = calendar.dateInterval(of: .month, for: now)?.start else { return false }
            return date >= start && date <= now
        }
    }

    private static func points(sessions: [SessionFact], range: StatsRange, now: Date, calendar: Calendar) -> [DayPoint] {
        switch range {
        case .day:
            return hourPoints(sessions: sessions, now: now, calendar: calendar)
        case .week:
            return dayPoints(sessions: sessions, interval: calendar.dateInterval(of: .weekOfYear, for: now), calendar: calendar)
        case .month:
            return dayPoints(sessions: sessions, interval: calendar.dateInterval(of: .month, for: now), calendar: calendar)
        }
    }

    private static func hourPoints(sessions: [SessionFact], now: Date, calendar: Calendar) -> [DayPoint] {
        let start = calendar.startOfDay(for: now)
        return (0..<24).compactMap { hour in
            guard let slot = calendar.date(byAdding: .hour, value: hour, to: start),
                  let next = calendar.date(byAdding: .hour, value: 1, to: slot) else { return nil }
            let seconds = sessions
                .filter { $0.start >= slot && $0.start < next }
                .reduce(0) { $0 + $1.seconds }
            return DayPoint(day: slot, minutes: Int(seconds / 60))
        }
    }

    private static func dayPoints(sessions: [SessionFact], interval: DateInterval?, calendar: Calendar) -> [DayPoint] {
        guard let interval else { return [] }
        var points: [DayPoint] = []
        var cursor = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        while cursor <= end {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            let seconds = sessions
                .filter { $0.start >= cursor && $0.start < next }
                .reduce(0) { $0 + $1.seconds }
            points.append(DayPoint(day: cursor, minutes: Int(seconds / 60)))
            cursor = next
        }
        return points
    }

    private static func topApps(_ sessions: [SessionFact]) -> [AppSlice] {
        var totals: [String: Double] = [:]
        for session in sessions {
            for app in session.apps {
                totals[app.name, default: 0] += app.seconds
            }
        }
        return totals
            .map { AppSlice(name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(8)
            .map { $0 }
    }

    static func appHours(_ sessions: [SessionFact]) -> [AppSlice] {
        topApps(sessions)
    }

    private static func topTitles(_ sessions: [SessionFact]) -> [TitleSlice] {
        var totals: [String: Double] = [:]
        for session in sessions {
            for title in session.titles where title.title.count > 2 {
                totals[title.title, default: 0] += title.seconds
            }
        }
        return totals
            .map { TitleSlice(title: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
            .prefix(12)
            .map { $0 }
    }
}

struct DistractionRule: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var app: String
    var title: String

    func matches(appName: String, title windowTitle: String) -> Bool {
        let appQuery = app.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleQuery = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if appQuery.isEmpty && titleQuery.isEmpty { return false }
        let appHit = appQuery.isEmpty || Self.hit(appQuery, appName)
        let titleHit = titleQuery.isEmpty || Self.hit(titleQuery, windowTitle)
        if !appQuery.isEmpty && !titleQuery.isEmpty { return appHit && titleHit }
        return appHit && titleHit
    }

    private static func hit(_ query: String, _ value: String) -> Bool {
        if let expression = try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            if expression.firstMatch(in: value, range: range) != nil { return true }
        }
        return value.localizedCaseInsensitiveContains(query)
    }
}

extension DistractionRule {
    static let presets: [DistractionRule] = [
        DistractionRule(
            id: "social-web",
            app: "Safari|Chrome|Firefox|Edge|Brave|Arc|Orion",
            title: "YouTube|Twitter|Facebook|Instagram|TikTok|Reddit|Twitch|Netflix|微博|哔哩哔哩|Bilibili|知乎|小红书|抖音|微信"
        ),
        DistractionRule(id: "messages", app: "Messages", title: ""),
        DistractionRule(id: "mail", app: "Mail", title: ""),
        DistractionRule(id: "wechat", app: "WeChat|微信", title: ""),
        DistractionRule(id: "qq", app: "QQ", title: ""),
        DistractionRule(id: "telegram", app: "Telegram", title: ""),
        DistractionRule(id: "whatsapp", app: "WhatsApp", title: ""),
        DistractionRule(id: "discord", app: "Discord", title: ""),
        DistractionRule(id: "x", app: "^X$|Twitter", title: ""),
        DistractionRule(id: "weibo", app: "Weibo|微博", title: ""),
        DistractionRule(id: "music", app: "Music|Spotify|QQMusic|NeteaseMusic|网易云音乐", title: ""),
        DistractionRule(id: "video", app: "TV|iQIYI|TencentVideo|哔哩哔哩", title: "")
    ]

    static func resolved(_ current: [DistractionRule]) -> [DistractionRule] {
        if current.isEmpty || isLegacyDefault(current) {
            return presets
        }
        return current
    }

    private static func isLegacyDefault(_ current: [DistractionRule]) -> Bool {
        guard current.count == 2 else { return false }
        let messages = current.contains { $0.id == "messages" && $0.app == "Messages" && $0.title.isEmpty }
        let mail = current.contains { $0.id == "mail" && $0.app == "Mail" && $0.title.isEmpty }
        return messages && mail
    }
}
