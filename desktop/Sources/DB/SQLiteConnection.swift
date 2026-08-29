import Foundation
import SQLite3

/// `sqlite3_bind_text`'s special "copy this string, don't assume it
/// outlives the call" destructor. Not directly importable as a Swift
/// constant from the C header (it's the macro `((sqlite3_destructor_type)-1)`),
/// so it's reconstructed the same way every hand-rolled Swift SQLite
/// wrapper does.
private let SQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A minimal, hand-rolled wrapper over the C `sqlite3` API — no
/// third-party package dependency, `import SQLite3` against the system
/// `libsqlite3` already part of the macOS SDK, same "hand-roll it against
/// the platform SDK" posture `Exporting`'s ZIP writer and
/// `PDFReportExporter` already use. Not a general-purpose SQL layer:
/// `ClientStore` only ever needs "get the JSON blob for this key" / "set
/// it," so this implements exactly that (a single `kv` table) plus a
/// transaction wrapper, nothing more.
///
/// `@unchecked Sendable`: this type is never used outside `ClientStore`,
/// which is itself an `actor` — every call into this connection is
/// already serialized by Swift concurrency's actor isolation before it
/// reaches here, so the underlying `OpaquePointer`'s lack of thread-safety
/// annotations is a non-issue in practice, not an unchecked risk.
final class SQLiteConnection: @unchecked Sendable {
    enum SQLiteConnectionError: Error, CustomStringConvertible {
        case openFailed(String)
        case execFailed(String)
        case stepFailed(String)

        var description: String {
            switch self {
            case .openFailed(let message): return "SQLite open failed: \(message)"
            case .execFailed(let message): return "SQLite exec failed: \(message)"
            case .stepFailed(let message): return "SQLite step failed: \(message)"
            }
        }
    }

    private let db: OpaquePointer

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let openResult = sqlite3_open_v2(path, &handle, flags, nil)
        guard openResult == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 returned \(openResult)"
            if let handle { sqlite3_close(handle) }
            throw SQLiteConnectionError.openFailed(message)
        }
        self.db = handle

        // WAL mode: a real crash-safety property the prior JSON-file
        // store never had. A killed process mid-write leaves the database
        // in its last COMMITted state, never a half-written file — unlike
        // 15 separate `Data.write(to:options:.atomic)` calls, where each
        // individual write was atomic but the SEQUENCE of several writes
        // making up one logical operation (e.g. upsert-then-log-activity)
        // never was.
        try exec("PRAGMA journal_mode=WAL;")
        try exec("""
            CREATE TABLE IF NOT EXISTS kv (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """)
    }

    deinit {
        sqlite3_close(db)
    }

    func exec(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorPointer)
            throw SQLiteConnectionError.execFailed(message)
        }
    }

    /// The JSON text stored for `key`, or `nil` if no row exists — the
    /// same "absent means never written" contract the old per-file
    /// `FileManager.default.fileExists` check had.
    func getValue(forKey key: String) throws -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT value FROM kv WHERE key = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteConnectionError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, key, -1, SQLiteTransient)
        let stepResult = sqlite3_step(statement)
        switch stepResult {
        case SQLITE_ROW:
            guard let cString = sqlite3_column_text(statement, 0) else { return nil }
            return String(cString: cString)
        case SQLITE_DONE:
            return nil
        default:
            throw SQLiteConnectionError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Upserts the JSON text for `key` — a single statement (`ON CONFLICT
    /// ... DO UPDATE`), not a separate exists-check-then-insert-or-update,
    /// so this is itself one atomic operation.
    func setValue(_ value: String, forKey key: String) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let sql = "INSERT INTO kv (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteConnectionError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, key, -1, SQLiteTransient)
        sqlite3_bind_text(statement, 2, value, -1, SQLiteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteConnectionError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    /// Deletes the row for `key` — a no-op, not an error, if it doesn't
    /// exist, same posture `clearPeriodLock`'s old file-existence check had.
    func deleteValue(forKey key: String) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "DELETE FROM kv WHERE key = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteConnectionError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_bind_text(statement, 1, key, -1, SQLiteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteConnectionError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}
