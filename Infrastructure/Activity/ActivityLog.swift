import Foundation
import SQLite3

struct ActivitySample: Equatable, Sendable, Identifiable {
    var id: Int
    var sessionID: String
    var capturedAt: Date
    var appName: String
    var windowTitle: String
    var bundleID: String
}

enum ActivityLogError: Error {
    case open(String)
    case statement(String)
}

actor ActivityLog {
    private nonisolated(unsafe) var db: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "open"
            if let handle { sqlite3_close(handle) }
            throw ActivityLogError.open(message)
        }
        db = handle
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
        CREATE TABLE IF NOT EXISTS samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            captured_at REAL NOT NULL,
            app_name TEXT NOT NULL,
            window_title TEXT NOT NULL,
            bundle_id TEXT NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS samples_session ON samples(session_id);")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func append(sessionID: String, at date: Date, app: String, title: String, bundleID: String) throws {
        let sql = "INSERT INTO samples (session_id, captured_at, app_name, window_title, bundle_id) VALUES (?, ?, ?, ?, ?);"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, sessionID)
        sqlite3_bind_double(statement, 2, date.timeIntervalSince1970)
        bind(statement, 3, app)
        bind(statement, 4, title)
        bind(statement, 5, bundleID)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ActivityLogError.statement(message)
        }
    }

    func samples(sessionID: String) throws -> [ActivitySample] {
        let sql = "SELECT id, session_id, captured_at, app_name, window_title, bundle_id FROM samples WHERE session_id = ? ORDER BY captured_at ASC;"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, sessionID)
        return rows(statement)
    }

    func delete(sessionID: String) throws {
        let statement = try prepare("DELETE FROM samples WHERE session_id = ?;")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, sessionID)
        sqlite3_step(statement)
    }

    func deleteAll() throws {
        try exec("DELETE FROM samples;")
    }

    static func slices(from samples: [ActivitySample]) -> (apps: [AppSlice], titles: [TitleSlice], switches: Int, primary: String?) {
        guard !samples.isEmpty else { return ([], [], 0, nil) }
        var appSeconds: [String: Double] = [:]
        var titleSeconds: [String: Double] = [:]
        var switches = 0
        if samples.count == 1 {
            appSeconds[samples[0].appName] = 0
            return ([AppSlice(name: samples[0].appName, seconds: 0)], [], 0, samples[0].appName)
        }
        var last = samples[0].appName
        for index in 1..<samples.count {
            let delta = min(120, max(0, samples[index].capturedAt.timeIntervalSince(samples[index - 1].capturedAt)))
            let previous = samples[index - 1]
            if SystemChrome.isIgnored(appName: previous.appName, bundleID: previous.bundleID) {
                if samples[index].appName != last {
                    switches += 1
                    last = samples[index].appName
                }
                continue
            }
            appSeconds[previous.appName, default: 0] += delta
            if !previous.windowTitle.isEmpty {
                titleSeconds[previous.windowTitle, default: 0] += delta
            }
            if samples[index].appName != last {
                switches += 1
                last = samples[index].appName
            }
        }
        let apps = appSeconds.map { AppSlice(name: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
        let titles = titleSeconds.map { TitleSlice(title: $0.key, seconds: $0.value) }.sorted { $0.seconds > $1.seconds }
        return (apps, titles, switches, apps.first?.name)
    }

    private nonisolated func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "exec"
            sqlite3_free(error)
            throw ActivityLogError.statement(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ActivityLogError.statement(message)
        }
        return statement
    }

    private var message: String {
        guard let db else { return "closed" }
        return String(cString: sqlite3_errmsg(db))
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ text: String) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, index, text, -1, transient)
    }

    private func rows(_ statement: OpaquePointer?) -> [ActivitySample] {
        var result: [ActivitySample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let title = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let app = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let session = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let bundle = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
            result.append(ActivitySample(
                id: Int(sqlite3_column_int64(statement, 0)),
                sessionID: session,
                capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                appName: app,
                windowTitle: title,
                bundleID: bundle
            ))
        }
        return result
    }
}
