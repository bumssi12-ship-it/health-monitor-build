import Foundation
import SQLite3

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "HealthMonitor.Database", qos: .utility)
    private(set) var databaseURL: URL?

    private init() {}

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Initialization / Schema

    func initializeDatabase() {
        queue.sync {
            guard db == nil else { return }

            let url = AppPaths.protectedDataDirectory
                .appendingPathComponent("health_monitor.sqlite3")
            databaseURL = url

            guard sqlite3_open(url.path, &db) == SQLITE_OK else {
                AppLogger.shared.error("SQLite open failed")
                if let db {
                    sqlite3_close(db)
                    self.db = nil
                }
                return
            }

            executeUnsafe("PRAGMA journal_mode=WAL;")
            executeUnsafe("PRAGMA synchronous=NORMAL;")
            executeUnsafe("PRAGMA foreign_keys=ON;")
            executeUnsafe("PRAGMA busy_timeout=5000;")

            migrateUnsafe()
            applyFileProtection()
            excludeDatabaseFromBackup()
        }
    }

    private func migrateUnsafe() {
        let previousVersion = userVersionUnsafe()

        createCurrentSchemaUnsafe()

        if !columnExistsUnsafe(table: "symptoms", column: "event_id") {
            executeUnsafe("ALTER TABLE symptoms ADD COLUMN event_id TEXT;")
        }

        if !columnExistsUnsafe(table: "orthostatic_sessions", column: "event_id") {
            executeUnsafe("ALTER TABLE orthostatic_sessions ADD COLUMN event_id TEXT;")
        }

        if !columnExistsUnsafe(table: "medications", column: "event_id") {
            executeUnsafe("ALTER TABLE medications ADD COLUMN event_id TEXT;")
        }

        if previousVersion < 5 {
            executeUnsafe("""
            UPDATE symptoms
            SET event_id = 'local-' || lower(hex(randomblob(16)))
            WHERE event_id IS NULL OR event_id = '';
            """)

            executeUnsafe("""
            UPDATE medications
            SET event_id = 'local-' || lower(hex(randomblob(16)))
            WHERE event_id IS NULL OR event_id = '';
            """)

            executeUnsafe("""
            UPDATE orthostatic_sessions
            SET event_id = 'local-' || lower(hex(randomblob(16)))
            WHERE event_id IS NULL OR event_id = '';
            """)
        }

        createCurrentIndexesUnsafe()

        if previousVersion < 4 {
            // V4 switched step counts from raw-sample summation to HealthKit
            // daily statistics. Remove any legacy cached raw step rows.
            executeUnsafe("DELETE FROM health_samples WHERE type = 'step_count';")
        }

        setUserVersionUnsafe(5)
        AppLogger.shared.info(
            "Database schema ready. previous=\(previousVersion), current=5"
        )
    }

    private func createCurrentSchemaUnsafe() {
        executeUnsafe("""
        CREATE TABLE IF NOT EXISTS health_samples (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sample_uuid TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL,
            start_at REAL NOT NULL,
            end_at REAL NOT NULL,
            value REAL NOT NULL,
            unit TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT ''
        );
        """)

        executeUnsafe("""
        CREATE TABLE IF NOT EXISTS symptoms (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT,
            timestamp REAL NOT NULL,
            symptom TEXT NOT NULL,
            posture TEXT NOT NULL,
            severity INTEGER NOT NULL,
            heart_rate REAL,
            note TEXT NOT NULL DEFAULT ''
        );
        """)

        executeUnsafe("""
        CREATE TABLE IF NOT EXISTS medications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT,
            timestamp REAL NOT NULL,
            name TEXT NOT NULL,
            dose REAL,
            unit TEXT NOT NULL DEFAULT 'mg',
            note TEXT NOT NULL DEFAULT ''
        );
        """)

        executeUnsafe("""
        CREATE TABLE IF NOT EXISTS orthostatic_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id TEXT,
            timestamp REAL NOT NULL,
            baseline_hr REAL,
            peak_standing_hr REAL,
            final_standing_hr REAL,
            peak_delta REAL,
            final_delta REAL,
            duration_seconds INTEGER NOT NULL,
            completed INTEGER NOT NULL,
            note TEXT NOT NULL DEFAULT ''
        );
        """)

        executeUnsafe("""
        CREATE TABLE IF NOT EXISTS daily_metrics (
            day_start REAL NOT NULL,
            type TEXT NOT NULL,
            value REAL NOT NULL,
            unit TEXT NOT NULL,
            PRIMARY KEY(day_start, type)
        );
        """)
    }

    private func createCurrentIndexesUnsafe() {
        executeUnsafe("""
        CREATE INDEX IF NOT EXISTS idx_health_type_start
        ON health_samples(type, start_at);
        """)

        executeUnsafe("""
        CREATE INDEX IF NOT EXISTS idx_symptom_timestamp
        ON symptoms(timestamp);
        """)

        executeUnsafe("""
        CREATE INDEX IF NOT EXISTS idx_medication_timestamp
        ON medications(timestamp);
        """)

        executeUnsafe("""
        CREATE INDEX IF NOT EXISTS idx_orthostatic_timestamp
        ON orthostatic_sessions(timestamp);
        """)

        executeUnsafe("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_medications_event_id_unique
        ON medications(event_id)
        WHERE event_id IS NOT NULL;
        """)

        executeUnsafe("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_symptoms_event_id_unique
        ON symptoms(event_id)
        WHERE event_id IS NOT NULL;
        """)

        executeUnsafe("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_orthostatic_event_id_unique
        ON orthostatic_sessions(event_id)
        WHERE event_id IS NOT NULL;
        """)

        executeUnsafe("""
        CREATE INDEX IF NOT EXISTS idx_daily_metric_type_day
        ON daily_metrics(type, day_start);
        """)
    }

    private func executeUnsafe(_ sql: String) {
        guard let db else { return }
        var error: UnsafeMutablePointer<Int8>?

        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown SQLite error"
            if let error {
                sqlite3_free(error)
            }
            AppLogger.shared.error("SQLite: \(message)")
        }
    }

    private func columnExistsUnsafe(table: String, column: String) -> Bool {
        guard let db else { return false }

        let sql = "PRAGMA table_info(\(table));"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let raw = sqlite3_column_text(stmt, 1),
               String(cString: raw) == column {
                return true
            }
        }

        return false
    }

    private func userVersionUnsafe() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func setUserVersionUnsafe(_ version: Int) {
        executeUnsafe("PRAGMA user_version=\(version);")
    }

    func userVersion() -> Int {
        queue.sync {
            userVersionUnsafe()
        }
    }

    // MARK: - File Protection

    private func applyFileProtection() {
        #if os(iOS)
        guard let databaseURL else { return }

        for url in databaseFiles(databaseURL) where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }
        #endif
    }

    private func excludeDatabaseFromBackup() {
        #if os(iOS)
        guard let databaseURL else { return }

        for var url in databaseFiles(databaseURL) where FileManager.default.fileExists(atPath: url.path) {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        #endif
    }

    private func databaseFiles(_ databaseURL: URL) -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
    }

    // MARK: - HealthKit Transactional Persistence

    func applyHealthKitChanges(
        samples: [HealthSampleRecord],
        deletedUUIDs: [UUID],
        completion: @escaping (Bool) -> Void
    ) {
        queue.async {
            guard let db = self.db else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            var success = true

            let insertSQL = """
            INSERT OR IGNORE INTO health_samples
            (sample_uuid, type, start_at, end_at, value, unit, source)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            var insertStmt: OpaquePointer?

            if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) != SQLITE_OK {
                success = false
            }

            if success, let insertStmt {
                for sample in samples {
                    sqlite3_reset(insertStmt)
                    sqlite3_clear_bindings(insertStmt)

                    sqlite3_bind_text(insertStmt, 1, sample.uuid, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(insertStmt, 2, sample.type.rawValue, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(insertStmt, 3, sample.start.timeIntervalSince1970)
                    sqlite3_bind_double(insertStmt, 4, sample.end.timeIntervalSince1970)
                    sqlite3_bind_double(insertStmt, 5, sample.value)
                    sqlite3_bind_text(insertStmt, 6, sample.unit, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(insertStmt, 7, sample.source, -1, SQLITE_TRANSIENT)

                    if sqlite3_step(insertStmt) != SQLITE_DONE {
                        success = false
                        break
                    }
                }
            }

            if let insertStmt {
                sqlite3_finalize(insertStmt)
            }

            if success, !deletedUUIDs.isEmpty {
                let deleteSQL = "DELETE FROM health_samples WHERE sample_uuid = ?;"
                var deleteStmt: OpaquePointer?

                if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) != SQLITE_OK {
                    success = false
                }

                if success, let deleteStmt {
                    for uuid in deletedUUIDs {
                        sqlite3_reset(deleteStmt)
                        sqlite3_clear_bindings(deleteStmt)
                        sqlite3_bind_text(
                            deleteStmt,
                            1,
                            uuid.uuidString,
                            -1,
                            SQLITE_TRANSIENT
                        )

                        if sqlite3_step(deleteStmt) != SQLITE_DONE {
                            success = false
                            break
                        }
                    }
                }

                if let deleteStmt {
                    sqlite3_finalize(deleteStmt)
                }
            }

            success = self.finishTransactionUnsafe(db: db, success: success)

            if !success {
                AppLogger.shared.error(
                    "Atomic HealthKit DB apply failed; anchor will not advance"
                )
            }

            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    func replaceDailyMetrics(
        for metric: HealthMetric,
        from: Date,
        to: Date,
        records: [DailyMetricRecord],
        completion: @escaping (Bool) -> Void
    ) {
        queue.async {
            guard let db = self.db else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            var success = true

            let deleteSQL = """
            DELETE FROM daily_metrics
            WHERE type = ? AND day_start >= ? AND day_start < ?;
            """
            var deleteStmt: OpaquePointer?

            if sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStmt, nil) != SQLITE_OK {
                success = false
            }

            if success, let deleteStmt {
                sqlite3_bind_text(deleteStmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
                sqlite3_bind_double(deleteStmt, 2, from.timeIntervalSince1970)
                sqlite3_bind_double(deleteStmt, 3, to.timeIntervalSince1970)

                if sqlite3_step(deleteStmt) != SQLITE_DONE {
                    success = false
                }
            }

            if let deleteStmt {
                sqlite3_finalize(deleteStmt)
            }

            if success, !records.isEmpty {
                let insertSQL = """
                INSERT INTO daily_metrics(day_start, type, value, unit)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(day_start, type)
                DO UPDATE SET value = excluded.value, unit = excluded.unit;
                """
                var insertStmt: OpaquePointer?

                if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) != SQLITE_OK {
                    success = false
                }

                if success, let insertStmt {
                    for record in records {
                        sqlite3_reset(insertStmt)
                        sqlite3_clear_bindings(insertStmt)

                        sqlite3_bind_double(
                            insertStmt,
                            1,
                            record.dayStart.timeIntervalSince1970
                        )
                        sqlite3_bind_text(
                            insertStmt,
                            2,
                            record.type.rawValue,
                            -1,
                            SQLITE_TRANSIENT
                        )
                        sqlite3_bind_double(insertStmt, 3, record.value)
                        sqlite3_bind_text(
                            insertStmt,
                            4,
                            record.unit,
                            -1,
                            SQLITE_TRANSIENT
                        )

                        if sqlite3_step(insertStmt) != SQLITE_DONE {
                            success = false
                            break
                        }
                    }
                }

                if let insertStmt {
                    sqlite3_finalize(insertStmt)
                }
            }

            success = self.finishTransactionUnsafe(db: db, success: success)

            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    private func finishTransactionUnsafe(db: OpaquePointer, success: Bool) -> Bool {
        guard success else {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return false
        }

        guard sqlite3_exec(db, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            return false
        }

        return true
    }

    // MARK: - Daily Metrics

    func dailyMetricValue(for metric: HealthMetric, dayStart: Date) -> Double? {
        queue.sync {
            guard let db else { return nil }

            let sql = """
            SELECT value
            FROM daily_metrics
            WHERE type = ? AND day_start = ?
            LIMIT 1;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return nil
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, dayStart.timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return sqlite3_column_double(stmt, 0)
        }
    }

    func dailyMetricCoverageCount(
        for metric: HealthMetric,
        from: Date,
        to: Date
    ) -> Int {
        queue.sync {
            guard let db else { return 0 }

            let sql = """
            SELECT COUNT(*)
            FROM daily_metrics
            WHERE type = ? AND day_start >= ? AND day_start < ?;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return 0
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, to.timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    func averageDailyMetric(
        for metric: HealthMetric,
        from: Date,
        to: Date
    ) -> Double? {
        queue.sync {
            guard let db else { return nil }

            let sql = """
            SELECT AVG(value)
            FROM daily_metrics
            WHERE type = ? AND day_start >= ? AND day_start < ?;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return nil
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, to.timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            guard sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
            return sqlite3_column_double(stmt, 0)
        }
    }

    // MARK: - User Events

    func addSymptom(
        eventID: String? = nil,
        timestamp: Date = Date(),
        symptom: String,
        posture: String,
        severity: Int,
        heartRate: Double?,
        note: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        let stableEventID = eventID ?? UUID().uuidString

        queue.async {
            guard let db = self.db else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            let sql = """
            INSERT OR IGNORE INTO symptoms
            (event_id, timestamp, symptom, posture, severity, heart_rate, note)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            defer { sqlite3_finalize(stmt) }

            self.bindOptionalText(stableEventID, stmt, 1)
            sqlite3_bind_double(stmt, 2, timestamp.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, symptom, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, posture, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 5, Int32(max(0, min(10, severity))))
            self.bindOptionalDouble(heartRate, stmt, 6)
            sqlite3_bind_text(stmt, 7, note, -1, SQLITE_TRANSIENT)

            let success = sqlite3_step(stmt) == SQLITE_DONE
            DispatchQueue.main.async { completion?(success) }
        }
    }

    func addMedication(
        eventID: String? = nil,
        date: Date,
        name: String,
        dose: Double?,
        unit: String,
        note: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        let stableEventID = eventID ?? UUID().uuidString

        queue.async {
            guard let db = self.db else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            let sql = """
            INSERT OR IGNORE INTO medications(
                event_id, timestamp, name, dose, unit, note
            )
            VALUES (?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            defer { sqlite3_finalize(stmt) }

            self.bindOptionalText(stableEventID, stmt, 1)
            sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, name, -1, SQLITE_TRANSIENT)
            self.bindOptionalDouble(dose, stmt, 4)
            sqlite3_bind_text(stmt, 5, unit, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, note, -1, SQLITE_TRANSIENT)

            let success = sqlite3_step(stmt) == SQLITE_DONE
            DispatchQueue.main.async { completion?(success) }
        }
    }

    func addOrthostaticSession(
        eventID: String? = nil,
        timestamp: Date,
        baselineHeartRate: Double?,
        peakStandingHeartRate: Double?,
        finalStandingHeartRate: Double?,
        peakDelta: Double?,
        finalDelta: Double?,
        durationSeconds: Int,
        completed: Bool,
        note: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        let stableEventID = eventID ?? UUID().uuidString

        queue.async {
            guard let db = self.db else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            let sql = """
            INSERT OR IGNORE INTO orthostatic_sessions(
                event_id, timestamp, baseline_hr, peak_standing_hr,
                final_standing_hr, peak_delta, final_delta,
                duration_seconds, completed, note
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            defer { sqlite3_finalize(stmt) }

            self.bindOptionalText(stableEventID, stmt, 1)
            sqlite3_bind_double(stmt, 2, timestamp.timeIntervalSince1970)
            self.bindOptionalDouble(baselineHeartRate, stmt, 3)
            self.bindOptionalDouble(peakStandingHeartRate, stmt, 4)
            self.bindOptionalDouble(finalStandingHeartRate, stmt, 5)
            self.bindOptionalDouble(peakDelta, stmt, 6)
            self.bindOptionalDouble(finalDelta, stmt, 7)
            sqlite3_bind_int(stmt, 8, Int32(max(0, durationSeconds)))
            sqlite3_bind_int(stmt, 9, completed ? 1 : 0)
            sqlite3_bind_text(stmt, 10, note, -1, SQLITE_TRANSIENT)

            let success = sqlite3_step(stmt) == SQLITE_DONE
            DispatchQueue.main.async { completion?(success) }
        }
    }

    // MARK: - Health Queries


func latestSample(for metric: HealthMetric) -> LatestMetricRecord? {
    queue.sync {
        guard let db else { return nil }

        let sql = """
        SELECT value, start_at
        FROM health_samples
        WHERE type = ?
        ORDER BY start_at DESC
        LIMIT 1;
        """
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        return LatestMetricRecord(
            value: sqlite3_column_double(stmt, 0),
            timestamp: Date(
                timeIntervalSince1970: sqlite3_column_double(stmt, 1)
            )
        )
    }
}

func resetHealthCache(completion: @escaping (Bool) -> Void) {
    queue.async {
        guard let db = self.db else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        var success = sqlite3_exec(
            db,
            "DELETE FROM health_samples;",
            nil,
            nil,
            nil
        ) == SQLITE_OK

        if success {
            success = sqlite3_exec(
                db,
                "DELETE FROM daily_metrics;",
                nil,
                nil,
                nil
            ) == SQLITE_OK
        }

        success = self.finishTransactionUnsafe(
            db: db,
            success: success
        )

        DispatchQueue.main.async {
            completion(success)
        }
    }
}

    func latestValue(
        for metric: HealthMetric,
        since: Date? = nil
    ) -> Double? {
        queue.sync {
            guard let db else { return nil }

            var sql = """
            SELECT value
            FROM health_samples
            WHERE type = ?
            """
            if since != nil {
                sql += " AND start_at >= ?"
            }
            sql += " ORDER BY start_at DESC LIMIT 1;"

            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return nil
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
            if let since {
                sqlite3_bind_double(stmt, 2, since.timeIntervalSince1970)
            }

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return sqlite3_column_double(stmt, 0)
        }
    }


func recordedDayCount(
    for metric: HealthMetric,
    from: Date,
    to: Date
) -> Int {
    queue.sync {
        guard let db else { return 0 }

        let sql = """
        SELECT start_at
        FROM health_samples
        WHERE type = ?
          AND start_at >= ?
          AND start_at < ?;
        """
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &stmt,
            nil
        ) == SQLITE_OK,
        let stmt else {
            return 0
        }
        defer {
            sqlite3_finalize(stmt)
        }

        sqlite3_bind_text(
            stmt,
            1,
            metric.rawValue,
            -1,
            SQLITE_TRANSIENT
        )
        sqlite3_bind_double(
            stmt,
            2,
            from.timeIntervalSince1970
        )
        sqlite3_bind_double(
            stmt,
            3,
            to.timeIntervalSince1970
        )

        let calendar = Calendar.current
        var days = Set<Date>()

        while sqlite3_step(stmt)
            == SQLITE_ROW {
            let date = Date(
                timeIntervalSince1970:
                    sqlite3_column_double(
                        stmt,
                        0
                    )
            )
            days.insert(
                calendar.startOfDay(
                    for: date
                )
            )
        }

        return days.count
    }
}

    func averageValue(
        for metric: HealthMetric,
        from: Date,
        to: Date
    ) -> Double? {
        queue.sync {
            guard let db else { return nil }

            let sql = """
            SELECT AVG(value)
            FROM health_samples
            WHERE type = ? AND start_at >= ? AND start_at < ?;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return nil
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, to.timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            guard sqlite3_column_type(stmt, 0) != SQLITE_NULL else { return nil }
            return sqlite3_column_double(stmt, 0)
        }
    }

    func symptomCount(from: Date, to: Date) -> Int {
        queue.sync {
            guard let db else { return 0 }

            let sql = """
            SELECT COUNT(*)
            FROM symptoms
            WHERE timestamp >= ? AND timestamp < ?;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return 0
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)

            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    // MARK: - User Event Reads

    func recentSymptoms(limit: Int = 50) -> [SymptomRecord] {
        queue.sync {
            guard let db else { return [] }

            let sql = """
            SELECT id, event_id, timestamp, symptom, posture,
                   severity, heart_rate, note
            FROM symptoms
            ORDER BY timestamp DESC
            LIMIT ?;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return []
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(max(0, limit)))
            var rows: [SymptomRecord] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    SymptomRecord(
                        id: sqlite3_column_int64(stmt, 0),
                        eventID: optionalText(stmt, 1),
                        timestamp: Date(
                            timeIntervalSince1970: sqlite3_column_double(stmt, 2)
                        ),
                        symptom: text(stmt, 3),
                        posture: text(stmt, 4),
                        severity: Int(sqlite3_column_int(stmt, 5)),
                        heartRate: optionalDouble(stmt, 6),
                        note: text(stmt, 7)
                    )
                )
            }

            return rows
        }
    }

    func recentMedications(limit: Int = 50) -> [MedicationRecord] {
        queue.sync {
            guard let db else { return [] }

            let sql = """
            SELECT id, event_id, timestamp, name, dose, unit, note
            FROM medications
            ORDER BY timestamp DESC
            LIMIT ?;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return []
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(max(0, limit)))
            var rows: [MedicationRecord] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    MedicationRecord(
                        id: sqlite3_column_int64(stmt, 0),
                        eventID: optionalText(stmt, 1),
                        timestamp: Date(
                            timeIntervalSince1970: sqlite3_column_double(stmt, 2)
                        ),
                        name: text(stmt, 3),
                        dose: optionalDouble(stmt, 4),
                        unit: text(stmt, 5),
                        note: text(stmt, 6)
                    )
                )
            }

            return rows
        }
    }

    func recentOrthostaticSessions(limit: Int = 50) -> [OrthostaticRecord] {
        queue.sync {
            guard let db else { return [] }

            let sql = """
            SELECT id, event_id, timestamp, baseline_hr,
                   peak_standing_hr, final_standing_hr,
                   peak_delta, final_delta, duration_seconds,
                   completed, note
            FROM orthostatic_sessions
            ORDER BY timestamp DESC
            LIMIT ?;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return []
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int(stmt, 1, Int32(max(0, limit)))
            var rows: [OrthostaticRecord] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append(
                    OrthostaticRecord(
                        id: sqlite3_column_int64(stmt, 0),
                        eventID: optionalText(stmt, 1),
                        timestamp: Date(
                            timeIntervalSince1970: sqlite3_column_double(stmt, 2)
                        ),
                        baselineHeartRate: optionalDouble(stmt, 3),
                        peakStandingHeartRate: optionalDouble(stmt, 4),
                        finalStandingHeartRate: optionalDouble(stmt, 5),
                        peakDelta: optionalDouble(stmt, 6),
                        finalDelta: optionalDouble(stmt, 7),
                        durationSeconds: Int(sqlite3_column_int(stmt, 8)),
                        completed: sqlite3_column_int(stmt, 9) == 1,
                        note: text(stmt, 10)
                    )
                )
            }

            return rows
        }
    }


// MARK: - Portable User Backup

func makeUserBackup() -> UserBackupEnvelope {
    let symptoms = recentSymptoms(limit: 100_000).map { item in
        UserBackupSymptom(
            eventID: item.eventID ?? "legacy-symptom-\(item.id)",
            timestamp: item.timestamp,
            symptom: item.symptom,
            posture: item.posture,
            severity: item.severity,
            heartRate: item.heartRate,
            note: item.note
        )
    }

    let medications = recentMedications(limit: 100_000).map { item in
        UserBackupMedication(
            eventID: item.eventID ?? "legacy-medication-\(item.id)",
            timestamp: item.timestamp,
            name: item.name,
            dose: item.dose,
            unit: item.unit,
            note: item.note
        )
    }

    let orthostatic = recentOrthostaticSessions(limit: 100_000).map { item in
        UserBackupOrthostatic(
            eventID: item.eventID ?? "legacy-orthostatic-\(item.id)",
            timestamp: item.timestamp,
            baselineHeartRate: item.baselineHeartRate,
            peakStandingHeartRate: item.peakStandingHeartRate,
            finalStandingHeartRate: item.finalStandingHeartRate,
            peakDelta: item.peakDelta,
            finalDelta: item.finalDelta,
            durationSeconds: item.durationSeconds,
            completed: item.completed,
            note: item.note
        )
    }

    return UserBackupEnvelope(
        formatVersion: UserBackupEnvelope.currentFormatVersion,
        generatedAt: Date(),
        symptoms: symptoms,
        medications: medications,
        orthostaticSessions: orthostatic
    )
}

func importUserBackup(
    _ backup: UserBackupEnvelope
) throws -> UserBackupImportSummary {
    let validated = try backup.validated()

    return try queue.sync {
        guard let db else {
            throw DatabaseBackupError.databaseUnavailable
        }

        guard sqlite3_exec(
            db,
            "BEGIN IMMEDIATE TRANSACTION;",
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw DatabaseBackupError.transactionFailed
        }

        do {
            let symptoms = try importSymptomsUnsafe(
                db: db,
                rows: validated.symptoms
            )
            let medications = try importMedicationsUnsafe(
                db: db,
                rows: validated.medications
            )
            let orthostatic = try importOrthostaticUnsafe(
                db: db,
                rows: validated.orthostaticSessions
            )

            guard sqlite3_exec(
                db,
                "COMMIT;",
                nil,
                nil,
                nil
            ) == SQLITE_OK else {
                sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
                throw DatabaseBackupError.transactionFailed
            }

            return UserBackupImportSummary(
                insertedSymptoms: symptoms,
                insertedMedications: medications,
                insertedOrthostaticSessions: orthostatic
            )
        } catch {
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }
}

private func importSymptomsUnsafe(
    db: OpaquePointer,
    rows: [UserBackupSymptom]
) throws -> Int {
    let sql = """
    INSERT OR IGNORE INTO symptoms(
        event_id, timestamp, symptom, posture,
        severity, heart_rate, note
    )
    VALUES (?, ?, ?, ?, ?, ?, ?);
    """
    var stmt: OpaquePointer?

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
          let stmt else {
        throw DatabaseBackupError.prepareFailed
    }
    defer { sqlite3_finalize(stmt) }

    var inserted = 0

    for row in rows {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        bindOptionalText(row.eventID, stmt, 1)
        sqlite3_bind_double(stmt, 2, row.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, row.symptom, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, row.posture, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, Int32(row.severity))
        bindOptionalDouble(row.heartRate, stmt, 6)
        sqlite3_bind_text(stmt, 7, row.note, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseBackupError.insertFailed
        }
        inserted += Int(sqlite3_changes(db))
    }

    return inserted
}

private func importMedicationsUnsafe(
    db: OpaquePointer,
    rows: [UserBackupMedication]
) throws -> Int {
    let sql = """
    INSERT OR IGNORE INTO medications(
        event_id, timestamp, name, dose, unit, note
    )
    VALUES (?, ?, ?, ?, ?, ?);
    """
    var stmt: OpaquePointer?

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
          let stmt else {
        throw DatabaseBackupError.prepareFailed
    }
    defer { sqlite3_finalize(stmt) }

    var inserted = 0

    for row in rows {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        bindOptionalText(row.eventID, stmt, 1)
        sqlite3_bind_double(stmt, 2, row.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, row.name, -1, SQLITE_TRANSIENT)
        bindOptionalDouble(row.dose, stmt, 4)
        sqlite3_bind_text(stmt, 5, row.unit, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 6, row.note, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseBackupError.insertFailed
        }
        inserted += Int(sqlite3_changes(db))
    }

    return inserted
}

private func importOrthostaticUnsafe(
    db: OpaquePointer,
    rows: [UserBackupOrthostatic]
) throws -> Int {
    let sql = """
    INSERT OR IGNORE INTO orthostatic_sessions(
        event_id, timestamp, baseline_hr, peak_standing_hr,
        final_standing_hr, peak_delta, final_delta,
        duration_seconds, completed, note
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """
    var stmt: OpaquePointer?

    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
          let stmt else {
        throw DatabaseBackupError.prepareFailed
    }
    defer { sqlite3_finalize(stmt) }

    var inserted = 0

    for row in rows {
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        bindOptionalText(row.eventID, stmt, 1)
        sqlite3_bind_double(stmt, 2, row.timestamp.timeIntervalSince1970)
        bindOptionalDouble(row.baselineHeartRate, stmt, 3)
        bindOptionalDouble(row.peakStandingHeartRate, stmt, 4)
        bindOptionalDouble(row.finalStandingHeartRate, stmt, 5)
        bindOptionalDouble(row.peakDelta, stmt, 6)
        bindOptionalDouble(row.finalDelta, stmt, 7)
        sqlite3_bind_int(stmt, 8, Int32(row.durationSeconds))
        sqlite3_bind_int(stmt, 9, row.completed ? 1 : 0)
        sqlite3_bind_text(stmt, 10, row.note, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseBackupError.insertFailed
        }
        inserted += Int(sqlite3_changes(db))
    }

    return inserted
}

    // MARK: - Sleep

    func sleepSummary(
        from: Date,
        to: Date
    ) -> (hours: Double, nights: Int)? {
        queue.sync {
            guard let db else { return nil }

            let sql = """
            SELECT start_at, end_at
            FROM health_samples
            WHERE type = ? AND end_at > ? AND start_at < ?
            ORDER BY start_at ASC;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return nil
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, HealthMetric.sleep.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, to.timeIntervalSince1970)

            var intervals: [(Double, Double)] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                let start = max(
                    sqlite3_column_double(stmt, 0),
                    from.timeIntervalSince1970
                )
                let end = min(
                    sqlite3_column_double(stmt, 1),
                    to.timeIntervalSince1970
                )

                if end > start {
                    intervals.append((start, end))
                }
            }

            guard !intervals.isEmpty else { return nil }

            var merged: [(Double, Double)] = []
            var currentStart = intervals[0].0
            var currentEnd = intervals[0].1

            for interval in intervals.dropFirst() {
                if interval.0 <= currentEnd {
                    currentEnd = max(currentEnd, interval.1)
                } else {
                    merged.append((currentStart, currentEnd))
                    currentStart = interval.0
                    currentEnd = interval.1
                }
            }

            merged.append((currentStart, currentEnd))

            let totalSeconds = merged.reduce(0.0) {
                $0 + ($1.1 - $1.0)
            }

            let calendar = Calendar.current
            let recordedNights = Set(
                merged.map {
                    calendar.startOfDay(
                        for: Date(timeIntervalSince1970: $0.1)
                    )
                }
            )

            return (
                hours: totalSeconds / 3600.0,
                nights: max(1, recordedNights.count)
            )
        }
    }

    // MARK: - Export

    func exportHealthSamples() -> [[String: String]] {
        queue.sync {
            guard let db else { return [] }

            let sql = """
            SELECT sample_uuid, type, start_at, end_at, value, unit, source
            FROM health_samples
            ORDER BY start_at ASC;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return []
            }
            defer { sqlite3_finalize(stmt) }

            let iso = ISO8601DateFormatter()
            var rows: [[String: String]] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append([
                    "sample_uuid": text(stmt, 0),
                    "type": text(stmt, 1),
                    "start_at": iso.string(
                        from: Date(
                            timeIntervalSince1970: sqlite3_column_double(stmt, 2)
                        )
                    ),
                    "end_at": iso.string(
                        from: Date(
                            timeIntervalSince1970: sqlite3_column_double(stmt, 3)
                        )
                    ),
                    "value": String(sqlite3_column_double(stmt, 4)),
                    "unit": text(stmt, 5),
                    "source": text(stmt, 6)
                ])
            }

            return rows
        }
    }

    func exportDailyMetrics() -> [[String: String]] {
        queue.sync {
            guard let db else { return [] }

            let sql = """
            SELECT day_start, type, value, unit
            FROM daily_metrics
            ORDER BY day_start ASC, type ASC;
            """
            var stmt: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return []
            }
            defer { sqlite3_finalize(stmt) }

            let iso = ISO8601DateFormatter()
            var rows: [[String: String]] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append([
                    "day_start": iso.string(
                        from: Date(
                            timeIntervalSince1970: sqlite3_column_double(stmt, 0)
                        )
                    ),
                    "type": text(stmt, 1),
                    "value": String(sqlite3_column_double(stmt, 2)),
                    "unit": text(stmt, 3)
                ])
            }

            return rows
        }
    }

    // MARK: - Integrity

    func quickCheck() -> [String] {
        pragmaMessages("PRAGMA quick_check;")
    }

    func integrityCheck() -> [String] {
        pragmaMessages("PRAGMA integrity_check;")
    }

    private func pragmaMessages(_ sql: String) -> [String] {
        queue.sync {
            guard let db else { return ["database unavailable"] }

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let stmt else {
                return ["prepare failed"]
            }
            defer { sqlite3_finalize(stmt) }

            var rows: [String] = []

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let value = sqlite3_column_text(stmt, 0) {
                    rows.append(String(cString: value))
                }
            }

            return rows
        }
    }

    // MARK: - Report

    func reportText() -> String {
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(
            byAdding: .day,
            value: -7,
            to: now
        ) ?? now

        let symptoms = recentSymptoms(limit: 100)
        let medications = recentMedications(limit: 100)
        let orthostatic = recentOrthostaticSessions(limit: 100)
            .filter { $0.timestamp >= sevenDaysAgo }

        var lines: [String] = []
        lines.append("Health Monitor - 7 Day Summary")
        lines.append(
            "Generated: \(DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .short))"
        )
        lines.append("")
        lines.append("Trend review only. This report is not a medical diagnosis.")
        lines.append("")
        lines.append(
            reportMetricLine(
                label: "Latest HR",
                sample: latestSample(for: .heartRate),
                unit: "bpm"
            )
        )
        lines.append(
            reportMetricLine(
                label: "Latest Resting HR",
                sample: latestSample(for: .restingHeartRate),
                unit: "bpm"
            )
        )
        lines.append(
            reportMetricLine(
                label: "Latest HRV",
                sample: latestSample(for: .hrv),
                unit: "ms"
            )
        )

        if let sleep = sleepSummary(from: sevenDaysAgo, to: now) {
            lines.append(
                "Last 7d sleep total: \(String(format: "%.1f", sleep.hours)) h across \(sleep.nights) recorded night(s)"
            )
        } else {
            lines.append("Last 7d sleep total: -")
        }

        lines.append(
            "Last 7d symptoms: \(symptomCount(from: sevenDaysAgo, to: now))"
        )

        let completedToday = calendar.startOfDay(for: now)
        let coverageStart = calendar.date(
            byAdding: .day,
            value: -7,
            to: completedToday
        ) ?? completedToday

        let rhrDays = recordedDayCount(
            for: .restingHeartRate,
            from: coverageStart,
            to: completedToday
        )
        let hrvDays = recordedDayCount(
            for: .hrv,
            from: coverageStart,
            to: completedToday
        )
        let stepDays = dailyMetricCoverageCount(
            for: .stepCount,
            from: coverageStart,
            to: completedToday
        )
        let sleepNights = sleepSummary(
            from: coverageStart,
            to: completedToday
        )?.nights ?? 0

        lines.append(
            "Data coverage (last 7 complete days): RHR \(rhrDays)/7, HRV \(hrvDays)/7, sleep \(sleepNights)/7, steps \(stepDays)/7"
        )
        lines.append("")
        lines.append("Recent symptoms:")

        for item in symptoms where item.timestamp >= sevenDaysAgo {
            let date = DateFormatter.localizedString(
                from: item.timestamp,
                dateStyle: .short,
                timeStyle: .short
            )
            let hrText = item.heartRate.map {
                String(format: "%.0f bpm", $0)
            } ?? "-"

            lines.append(
                "- \(date) | \(item.symptom) | \(item.posture) | severity \(item.severity)/10 | HR \(hrText) | \(item.note)"
            )
        }

        lines.append("")
        lines.append("Orthostatic checks:")

        for item in orthostatic {
            let date = DateFormatter.localizedString(
                from: item.timestamp,
                dateStyle: .short,
                timeStyle: .short
            )

            lines.append(
                "- \(date) | baseline \(format(item.baselineHeartRate)) | peak \(format(item.peakStandingHeartRate)) | final \(format(item.finalStandingHeartRate)) | peak delta \(signed(item.peakDelta)) | completed \(item.completed)"
            )
        }

        lines.append("")
        lines.append("Medication events:")

        for item in medications where item.timestamp >= sevenDaysAgo {
            let date = DateFormatter.localizedString(
                from: item.timestamp,
                dateStyle: .short,
                timeStyle: .short
            )
            let dose = item.dose.map {
                String(format: "%.1f", $0) + item.unit
            } ?? "-"

            lines.append(
                "- \(date) | \(item.name) | \(dose) | \(item.note)"
            )
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Binding / Row Helpers

    private func bindOptionalText(
        _ value: String?,
        _ stmt: OpaquePointer,
        _ index: Int32
    ) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindOptionalDouble(
        _ value: Double?,
        _ stmt: OpaquePointer,
        _ index: Int32
    ) {
        if let value {
            sqlite3_bind_double(stmt, index, value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func text(
        _ stmt: OpaquePointer,
        _ column: Int32
    ) -> String {
        guard let value = sqlite3_column_text(stmt, column) else { return "" }
        return String(cString: value)
    }

    private func optionalText(
        _ stmt: OpaquePointer,
        _ column: Int32
    ) -> String? {
        guard sqlite3_column_type(stmt, column) != SQLITE_NULL else { return nil }
        return text(stmt, column)
    }

    private func optionalDouble(
        _ stmt: OpaquePointer,
        _ column: Int32
    ) -> Double? {
        sqlite3_column_type(stmt, column) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(stmt, column)
    }


private func reportMetricLine(
    label: String,
    sample: LatestMetricRecord?,
    unit: String
) -> String {
    guard let sample else {
        return "\(label): -"
    }

    let timestamp = DateFormatter.localizedString(
        from: sample.timestamp,
        dateStyle: .short,
        timeStyle: .short
    )

    return "\(label): \(String(format: "%.1f", sample.value)) \(unit) @ \(timestamp)"
}

    private func format(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f", value)
    }

    private func signed(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%+.1f", value)
    }
}

enum DatabaseBackupError: LocalizedError {
    case databaseUnavailable
    case transactionFailed
    case prepareFailed
    case insertFailed

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "데이터베이스를 사용할 수 없습니다."
        case .transactionFailed:
            return "백업 복원 트랜잭션에 실패했습니다."
        case .prepareFailed:
            return "백업 복원 SQL 준비에 실패했습니다."
        case .insertFailed:
            return "백업 기록 저장에 실패했습니다."
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)
