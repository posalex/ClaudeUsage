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
	/// All stored usage metrics for this timestamp keyed by API field name
	/// (e.g. "five_hour", "seven_day", "seven_day_fable").
	let metrics: [String: Double]
	let sessionResetsAt: Date?
	/// true for synthetic records inserted during gap interpolation
	var isSynthetic: Bool = false

	/// Convenience accessors for the primary windows used across the UI.
	var sessionPercent: Double { metrics["five_hour"] ?? 0 }
	var weeklyPercent: Double { metrics["seven_day"] ?? 0 }

	/// Sorted list of metric keys for convenience when rendering legends.
	var metricKeys: [String] { metrics.keys.sorted() }
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
		createMetricsTable()
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

	/// Additional table that stores arbitrary usage metrics per history row
	/// so new model/limit keys (e.g. Fable) can be persisted without schema
	/// changes.
	private func createMetricsTable() {
		let sql = """
		CREATE TABLE IF NOT EXISTS usage_history_metrics (
		    id INTEGER PRIMARY KEY AUTOINCREMENT,
		    history_id INTEGER NOT NULL,
		    metric_key TEXT NOT NULL,
		    percent REAL NOT NULL,
		    FOREIGN KEY(history_id) REFERENCES usage_history(id) ON DELETE CASCADE
		);
		"""
		execute(sql)
		// Indexes for efficient lookup by history id / metric key
		execute("CREATE INDEX IF NOT EXISTS idx_usage_metrics_history_id ON usage_history_metrics(history_id);")
		execute("CREATE INDEX IF NOT EXISTS idx_usage_metrics_key ON usage_history_metrics(metric_key);")
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

	/// Persist a snapshot of all usage metrics. The dictionary keys are the
	/// raw API field names (e.g. "five_hour", "seven_day_fable").
	func record(metrics: [String: Double], sessionResetsAt: Date? = nil) {
		queue.async { [weak self] in
			guard let self, let db = self.db else { return }
			let insertHistorySQL = "INSERT INTO usage_history (timestamp, session_percent, weekly_percent, sonnet_percent, session_resets_at) VALUES (?, ?, ?, ?, ?)"
			var stmt: OpaquePointer?

			guard sqlite3_prepare_v2(db, insertHistorySQL, -1, &stmt, nil) == SQLITE_OK else { return }

			let now = Date()
			let nowTimestamp = now.timeIntervalSince1970
			let sessionPercent = metrics["five_hour"] ?? 0
			let weeklyPercent = metrics["seven_day"] ?? 0
			let sonnetPercent = metrics["seven_day_sonnet"]

			sqlite3_bind_double(stmt, 1, nowTimestamp)
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

			guard sqlite3_step(stmt) == SQLITE_DONE else {
				sqlite3_finalize(stmt)
				return
			}
			sqlite3_finalize(stmt)

			let historyId = sqlite3_last_insert_rowid(db)

			// Persist dynamic metrics; store all keys so future UI can render
			// every category, not just the current favourites.
			let metricsSQL = "INSERT INTO usage_history_metrics (history_id, metric_key, percent) VALUES (?, ?, ?)"
			var metricStmt: OpaquePointer?
			guard sqlite3_prepare_v2(db, metricsSQL, -1, &metricStmt, nil) == SQLITE_OK else { return }

			for (key, value) in metrics {
				sqlite3_reset(metricStmt)
				sqlite3_clear_bindings(metricStmt)
				sqlite3_bind_int64(metricStmt, 1, historyId)
				key.withCString { cStr in
					sqlite3_bind_text(metricStmt, 2, cStr, -1, nil)
					sqlite3_bind_double(metricStmt, 3, value)
					sqlite3_step(metricStmt)
				}
			}

			sqlite3_finalize(metricStmt)
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
			var rawRows: [(id: Int64, timestamp: Date, session: Double, weekly: Double, sonnet: Double?, resetsAt: Date?)] = []

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

				rawRows.append((id: id, timestamp: timestamp, session: session, weekly: weekly, sonnet: sonnet, resetsAt: resetsAt))
			}

			sqlite3_finalize(stmt)

			// Fetch dynamic metrics for the same time range and group them by history id.
			let metricsSql = """
			SELECT m.history_id, m.metric_key, m.percent
			FROM usage_history_metrics m
			JOIN usage_history h ON h.id = m.history_id
			WHERE h.timestamp >= ?
			ORDER BY m.history_id ASC
			"""
			var metricsStmt: OpaquePointer?
			var metricsByHistory: [Int64: [String: Double]] = [:]

			if sqlite3_prepare_v2(db, metricsSql, -1, &metricsStmt, nil) == SQLITE_OK {
				sqlite3_bind_double(metricsStmt, 1, startDate.timeIntervalSince1970)
				while sqlite3_step(metricsStmt) == SQLITE_ROW {
					let historyId = sqlite3_column_int64(metricsStmt, 0)
					guard let keyCStr = sqlite3_column_text(metricsStmt, 1) else { continue }
					let key = String(cString: keyCStr)
					let percent = sqlite3_column_double(metricsStmt, 2)

					var dict = metricsByHistory[historyId] ?? [:]
					dict[key] = percent
					metricsByHistory[historyId] = dict
				}
			}
			sqlite3_finalize(metricsStmt)

			// Build final records, falling back to the legacy columns when there
			// is no entry in the dynamic metrics table (old installations).
			var records: [UsageHistoryRecord] = []
			for row in rawRows {
				let storedMetrics = metricsByHistory[row.id]
				var metrics = storedMetrics ?? [:]

				// Rows from the pre-dynamic-metrics schema only have the legacy
				// Claude columns. New rows can contain a different provider (Codex),
				// so do not invent zero-valued Claude metrics for those rows.
				if storedMetrics == nil {
					metrics["five_hour"] = row.session
					metrics["seven_day"] = row.weekly
					if let sonnet = row.sonnet {
						metrics["seven_day_sonnet"] = sonnet
					}
				}

				records.append(UsageHistoryRecord(
					id: row.id,
					timestamp: row.timestamp,
					metrics: metrics,
					sessionResetsAt: row.resetsAt,
					isSynthetic: false
				))
			}

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

				if gap > gapThreshold,
				   current.metrics["five_hour"] != nil,
				   next.metrics["five_hour"] != nil,
				   let resetsAt = current.sessionResetsAt {
                    // Does the reset time fall within this gap?
                    if resetsAt > current.timestamp && resetsAt < next.timestamp {
                        // Calculate how far into the gap the reset occurs (0..1)
                        let fraction = resetsAt.timeIntervalSince(current.timestamp) / gap

						// Linearly interpolate all metrics across the gap. The
						// session window (five_hour) is special: it resets to 0 at
						// the reset point, while weekly/model windows continue
						// smoothly.
						var interpolatedMetrics: [String: Double] = [:]
						interpolatedMetrics["five_hour"] = 0
						let allKeys = Set(current.metrics.keys).union(next.metrics.keys)
						for key in allKeys {
							if key == "five_hour" { continue }
							guard let cVal = current.metrics[key], let nVal = next.metrics[key] else { continue }
							let valueAtReset = cVal + (nVal - cVal) * fraction
							interpolatedMetrics[key] = valueAtReset
						}

						// Insert a synthetic record at the reset time
						result.append(UsageHistoryRecord(
							id: -1,
							timestamp: resetsAt,
							metrics: interpolatedMetrics,
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
