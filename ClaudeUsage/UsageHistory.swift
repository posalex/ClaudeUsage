import Foundation
import SQLite3

// MARK: - Chart Period

enum ChartPeriod: String, CaseIterable, Codable {
    case hour = "1H"
    case fiveHours = "5H"
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case threeMonths = "3M"
    case year = "1Y"
    case allTime = "All"

    var startDate: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .hour: return cal.date(byAdding: .hour, value: -1, to: now) ?? .distantPast
        case .fiveHours: return cal.date(byAdding: .hour, value: -5, to: now) ?? .distantPast
        case .day: return cal.date(byAdding: .day, value: -1, to: now) ?? .distantPast
        case .week: return cal.date(byAdding: .weekOfYear, value: -1, to: now) ?? .distantPast
        case .month: return cal.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        case .threeMonths: return cal.date(byAdding: .month, value: -3, to: now) ?? .distantPast
        case .year: return cal.date(byAdding: .year, value: -1, to: now) ?? .distantPast
        case .allTime: return .distantPast
        }
    }
}

// MARK: - History Record

struct UsageHistoryRecord: Identifiable, Sendable {
    let id: Int64
    let timestamp: Date
    let sessionPercent: Double
    let weeklyPercent: Double
    let sonnetPercent: Double?
    let sessionResetsAt: Date?
    /// true for synthetic records inserted during gap interpolation
    var isSynthetic: Bool = false
}

// MARK: - SQLite Usage History Store

class UsageHistoryStore {
    static let shared = UsageHistoryStore()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.github.posalex.claudeusage.sqlite", qos: .utility)

    private init() {
        openDatabase()
        createTable()
        migrateAddResetsAt()
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let fileManager = FileManager.default

        // Store in Application Support (no App Group to avoid permission dialogs)
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("UsageHistory: could not find Application Support directory")
            return
        }
        let dir = appSupport.appendingPathComponent("ClaudeUsage")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("usage_history.sqlite")

        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            print("UsageHistory: failed to open database at \(dbURL.path)")
        }

        // Enable WAL mode for better concurrent read/write performance
        execute("PRAGMA journal_mode=WAL;")
    }

    private func createTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS usage_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            session_percent REAL NOT NULL,
            weekly_percent REAL NOT NULL,
            sonnet_percent REAL,
            session_resets_at REAL
        );
        """
        execute(sql)

        // Index for time-range queries
        execute("CREATE INDEX IF NOT EXISTS idx_usage_timestamp ON usage_history(timestamp);")
    }

    /// Add the session_resets_at column if it doesn't already exist (migration for existing DBs).
    private func migrateAddResetsAt() {
        // SQLite ignores "IF NOT EXISTS" for columns, so check pragma first
        guard let db = db else { return }
        var stmt: OpaquePointer?
        var hasColumn = false
        if sqlite3_prepare_v2(db, "PRAGMA table_info(usage_history)", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let name = sqlite3_column_text(stmt, 1) {
                    if String(cString: name) == "session_resets_at" {
                        hasColumn = true
                        break
                    }
                }
            }
        }
        sqlite3_finalize(stmt)
        if !hasColumn {
            execute("ALTER TABLE usage_history ADD COLUMN session_resets_at REAL;")
        }
    }

    private func execute(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let err = errMsg {
                print("UsageHistory SQL error: \(String(cString: err))")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Record Data

    func record(sessionPercent: Double, weeklyPercent: Double, sonnetPercent: Double?, sessionResetsAt: Date? = nil) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            let sql = "INSERT INTO usage_history (timestamp, session_percent, weekly_percent, sonnet_percent, session_resets_at) VALUES (?, ?, ?, ?, ?)"
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, sessionPercent)
            sqlite3_bind_double(stmt, 3, weeklyPercent)

            if let sonnet = sonnetPercent {
                sqlite3_bind_double(stmt, 4, sonnet)
            } else {
                sqlite3_bind_null(stmt, 4)
            }

            if let resetsAt = sessionResetsAt {
                sqlite3_bind_double(stmt, 5, resetsAt.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 5)
            }

            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
        compactIfNeeded()
    }

    // MARK: - Fetch Data

    func fetch(since startDate: Date, completion: @escaping ([UsageHistoryRecord]) -> Void) {
        queue.async { [weak self] in
            guard let self, let db = self.db else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let sql = """
            SELECT id, timestamp, session_percent, weekly_percent, sonnet_percent, session_resets_at
            FROM usage_history
            WHERE timestamp >= ?
            ORDER BY timestamp ASC
            """
            var stmt: OpaquePointer?
            var records: [UsageHistoryRecord] = []

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            sqlite3_bind_double(stmt, 1, startDate.timeIntervalSince1970)

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
                let session = sqlite3_column_double(stmt, 2)
                let weekly = sqlite3_column_double(stmt, 3)
                let sonnet: Double? = sqlite3_column_type(stmt, 4) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_double(stmt, 4)
                let resetsAt: Date? = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))

                records.append(UsageHistoryRecord(
                    id: id,
                    timestamp: timestamp,
                    sessionPercent: session,
                    weeklyPercent: weekly,
                    sonnetPercent: sonnet,
                    sessionResetsAt: resetsAt
                ))
            }

            sqlite3_finalize(stmt)

            let interpolated = Self.interpolateGaps(in: records)
            DispatchQueue.main.async { completion(interpolated) }
        }
    }

    // MARK: - Gap Interpolation

    /// When there's a gap between two records (e.g. app was closed / Mac sleeping),
    /// insert synthetic records to show estimated reset behavior.
    ///
    /// If the last record before a gap has a `sessionResetsAt` time that falls
    /// within the gap, insert a synthetic 0% record at that reset time.
    /// The weekly percent is linearly interpolated across the gap.
    static func interpolateGaps(in records: [UsageHistoryRecord]) -> [UsageHistoryRecord] {
        guard records.count >= 2 else { return records }

        // A "gap" is when two consecutive records are more than 20 minutes apart
        let gapThreshold: TimeInterval = 20 * 60
        var result: [UsageHistoryRecord] = []

        for i in 0..<records.count {
            let current = records[i]
            result.append(current)

            if i + 1 < records.count {
                let next = records[i + 1]
                let gap = next.timestamp.timeIntervalSince(current.timestamp)

                if gap > gapThreshold, let resetsAt = current.sessionResetsAt {
                    // Does the reset time fall within this gap?
                    if resetsAt > current.timestamp && resetsAt < next.timestamp {
                        // Calculate how far into the gap the reset occurs (0..1)
                        let fraction = resetsAt.timeIntervalSince(current.timestamp) / gap

                        // Linearly interpolate weekly percent across the gap
                        let weeklyAtReset = current.weeklyPercent + (next.weeklyPercent - current.weeklyPercent) * fraction
                        let sonnetAtReset: Double? = {
                            if let cs = current.sonnetPercent, let ns = next.sonnetPercent {
                                return cs + (ns - cs) * fraction
                            }
                            return nil
                        }()

                        // Insert a synthetic 0% session record at the reset time
                        result.append(UsageHistoryRecord(
                            id: -1,
                            timestamp: resetsAt,
                            sessionPercent: 0,
                            weeklyPercent: weeklyAtReset,
                            sonnetPercent: sonnetAtReset,
                            sessionResetsAt: nil,
                            isSynthetic: true
                        ))
                    }
                }
            }
        }

        return result
    }

    // MARK: - Data Compaction

    private static let lastCompactionKey = "usageHistoryLastCompaction"

    /// Compact old records: keep full resolution for the last 7 days,
    /// downsample to one record per hour (max values) for anything older.
    /// Runs at most once per day to avoid unnecessary work.
    private func compactIfNeeded() {
        let now = Date()
        let lastCompaction = UserDefaults.standard.double(forKey: Self.lastCompactionKey)
        let oneDayAgo = now.addingTimeInterval(-24 * 3600).timeIntervalSince1970

        // Skip if we already compacted today
        guard lastCompaction < oneDayAgo else { return }

        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            self.compactOldRecords(db: db)
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastCompactionKey)
        }
    }

    /// For records older than 7 days, keep only the one with the highest
    /// session_percent per hour-bucket. Delete the rest.
    private func compactOldRecords(db: OpaquePointer) {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600).timeIntervalSince1970

        let sql = """
        DELETE FROM usage_history
        WHERE timestamp < ?
          AND id NOT IN (
            SELECT id FROM (
              SELECT id,
                     ROW_NUMBER() OVER (
                       PARTITION BY CAST(timestamp / 3600 AS INTEGER)
                       ORDER BY session_percent DESC, timestamp DESC
                     ) AS rn
              FROM usage_history
              WHERE timestamp < ?
            )
            WHERE rn = 1
          )
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_double(stmt, 1, sevenDaysAgo)
        sqlite3_bind_double(stmt, 2, sevenDaysAgo)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - Cleanup

    deinit {
        sqlite3_close(db)
    }
}
