import Foundation

final class ExportManager {
    static let shared = ExportManager()

    private init() {}

    func createExportBundle() throws -> [URL] {
        let fm = FileManager.default
        let root = AppPaths.protectedDataDirectory.appendingPathComponent("Exports", isDirectory: true)
        try fm.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let directory = root.appendingPathComponent(
            "HealthMonitorExport-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8))",
            isDirectory: true
        )

        try fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        try writeHealthCSV(to: directory.appendingPathComponent("health_samples.csv"))
        try writeDailyMetricsCSV(to: directory.appendingPathComponent("daily_metrics.csv"))
        try writeSymptomsCSV(to: directory.appendingPathComponent("symptoms.csv"))
        try writeOrthostaticCSV(to: directory.appendingPathComponent("orthostatic_sessions.csv"))
        try writeMedicationsCSV(to: directory.appendingPathComponent("medications.csv"))
        try writeSummaryJSON(to: directory.appendingPathComponent("summary.json"))
        try DatabaseManager.shared.reportText().write(
            to: directory.appendingPathComponent("report_7days.txt"),
            atomically: true,
            encoding: .utf8
        )

        SensitiveFileProtection.protectRecursively(directory)
        cleanupOldExports(in: root, keep: 3)
        AppLogger.shared.info("Export bundle created: \(directory.lastPathComponent)")

        return try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func writeDailyMetricsCSV(to url: URL) throws {
        let headers = ["day_start", "type", "value", "unit"]
        let rows = DatabaseManager.shared.exportDailyMetrics()
        try csv(headers: headers, rows: rows).write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeHealthCSV(to url: URL) throws {
        let headers = ["sample_uuid", "type", "start_at", "end_at", "value", "unit", "source"]
        let rows = DatabaseManager.shared.exportHealthSamples()
        try csv(headers: headers, rows: rows).write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeSymptomsCSV(to url: URL) throws {
        let iso = ISO8601DateFormatter()
        let rows = DatabaseManager.shared.recentSymptoms(limit: 100_000).map { item in
            [
                "event_id": item.eventID ?? "",
                "timestamp": iso.string(from: item.timestamp),
                "symptom": item.symptom,
                "posture": item.posture,
                "severity": String(item.severity),
                "heart_rate": item.heartRate.map(String.init) ?? "",
                "note": item.note
            ]
        }
        let headers = ["event_id", "timestamp", "symptom", "posture", "severity", "heart_rate", "note"]
        try csv(headers: headers, rows: rows).write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeOrthostaticCSV(to url: URL) throws {
        let iso = ISO8601DateFormatter()
        let rows = DatabaseManager.shared.recentOrthostaticSessions(limit: 100_000).map { item in
            [
                "event_id": item.eventID ?? "",
                "timestamp": iso.string(from: item.timestamp),
                "baseline_hr": item.baselineHeartRate.map(String.init) ?? "",
                "peak_standing_hr": item.peakStandingHeartRate.map(String.init) ?? "",
                "final_standing_hr": item.finalStandingHeartRate.map(String.init) ?? "",
                "peak_delta": item.peakDelta.map(String.init) ?? "",
                "final_delta": item.finalDelta.map(String.init) ?? "",
                "duration_seconds": String(item.durationSeconds),
                "completed": String(item.completed),
                "note": item.note
            ]
        }
        let headers = [
            "event_id", "timestamp", "baseline_hr", "peak_standing_hr",
            "final_standing_hr", "peak_delta", "final_delta",
            "duration_seconds", "completed", "note"
        ]
        try csv(headers: headers, rows: rows).write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeMedicationsCSV(to url: URL) throws {
        let iso = ISO8601DateFormatter()
        let rows = DatabaseManager.shared.recentMedications(limit: 100_000).map { item in
            [
                "event_id": item.eventID ?? "",
                "timestamp": iso.string(from: item.timestamp),
                "name": item.name,
                "dose": item.dose.map(String.init) ?? "",
                "unit": item.unit,
                "note": item.note
            ]
        }
        let headers = ["event_id", "timestamp", "name", "dose", "unit", "note"]
        try csv(headers: headers, rows: rows).write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeSummaryJSON(to url: URL) throws {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let sevenDaysAgo = calendar.date(
            byAdding: .day,
            value: -7,
            to: today
        ) ?? today

        let db = DatabaseManager.shared
        let sleepNights =
            db.sleepSummary(
                from: sevenDaysAgo,
                to: today
            )?.nights ?? 0

        let payload: [String: Any] = [
            "generated_at": ISO8601DateFormatter().string(from: now),
            "database_user_version": db.userVersion(),
            "last_health_sync_at": HealthKitManager.shared.lastSyncAt.map {
                ISO8601DateFormatter().string(from: $0)
            } ?? NSNull(),
            "health_anchor_count": HealthKitManager.shared.storedAnchorCount(),
            "coverage_last_7_complete_days": [
                "resting_hr_days": db.recordedDayCount(
                    for: .restingHeartRate,
                    from: sevenDaysAgo,
                    to: today
                ),
                "hrv_days": db.recordedDayCount(
                    for: .hrv,
                    from: sevenDaysAgo,
                    to: today
                ),
                "sleep_nights": sleepNights,
                "step_days": db.dailyMetricCoverageCount(
                    for: .stepCount,
                    from: sevenDaysAgo,
                    to: today
                )
            ],
            "note": "Trend review only. Not a medical diagnosis."
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func csv(headers: [String], rows: [[String: String]]) -> String {
        var lines = [headers.map(CSVSanitizer.escape).joined(separator: ",")]
        for row in rows {
            lines.append(headers.map { CSVSanitizer.escape(row[$0] ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func cleanupOldExports(in root: URL, keep: Int) {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let exports = urls
            .filter { $0.lastPathComponent.hasPrefix("HealthMonitorExport-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for old in exports.dropFirst(max(0, keep)) {
            try? fm.removeItem(at: old)
        }
    }

}
