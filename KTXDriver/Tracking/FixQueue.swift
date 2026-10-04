import Foundation
import SQLite3

/// Positions waiting to be posted, oldest first. Every fix goes through here so a dead zone,
/// a server error or the app being killed never loses one. SQLite, like the Android app's FixQueue.
final class FixQueue {

    struct Fix {
        let id: Int64
        let url: String
        let body: String
    }

    static let shared = FixQueue()

    /// About a week of 60-second fixes; beyond that drop the oldest rather than grow forever.
    private static let maxRows: Int64 = 10_000

    private var db: OpaquePointer?
    private let lock = NSLock()

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Readable while the phone is locked (after the first unlock since boot): tracking runs in a pocket.
        let path = dir.appendingPathComponent("fixes.sqlite").path
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
                           | SQLITE_OPEN_FILEPROTECTION_COMPLETEUNTILFIRSTUSERAUTHENTICATION, nil) != SQLITE_OK {
            NSLog("FixQueue: cannot open database: %@", String(cString: sqlite3_errmsg(db)))
        }
        exec("CREATE TABLE IF NOT EXISTS fix (id INTEGER PRIMARY KEY AUTOINCREMENT, url TEXT NOT NULL, body TEXT NOT NULL)")
    }

    func add(url: String, body: String) {
        lock.lock(); defer { lock.unlock() }
        withStatement("INSERT INTO fix (url, body) VALUES (?, ?)") { stmt in
            sqlite3_bind_text(stmt, 1, url, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, body, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
        }
        exec("DELETE FROM fix WHERE id <= (SELECT MAX(id) FROM fix) - \(Self.maxRows)")
    }

    func oldest(limit: Int) -> [Fix] {
        lock.lock(); defer { lock.unlock() }
        var fixes: [Fix] = []
        withStatement("SELECT id, url, body FROM fix ORDER BY id LIMIT \(limit)") { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                fixes.append(Fix(id: sqlite3_column_int64(stmt, 0),
                                 url: String(cString: sqlite3_column_text(stmt, 1)),
                                 body: String(cString: sqlite3_column_text(stmt, 2))))
            }
        }
        return fixes
    }

    func remove(id: Int64) {
        lock.lock(); defer { lock.unlock() }
        withStatement("DELETE FROM fix WHERE id = ?") { stmt in
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
        }
    }

    func count() -> Int {
        lock.lock(); defer { lock.unlock() }
        var n = 0
        withStatement("SELECT COUNT(*) FROM fix") { stmt in
            if sqlite3_step(stmt) == SQLITE_ROW { n = Int(sqlite3_column_int64(stmt, 0)) }
        }
        return n
    }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            NSLog("FixQueue: %@: %@", sql, String(cString: sqlite3_errmsg(db)))
        }
    }

    private func withStatement(_ sql: String, _ body: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("FixQueue: %@: %@", sql, String(cString: sqlite3_errmsg(db)))
            return
        }
        defer { sqlite3_finalize(stmt) }
        body(stmt)
    }
}

/// SQLite copies bound strings immediately (the Swift string's buffer is temporary).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
