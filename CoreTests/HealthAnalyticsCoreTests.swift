import Foundation
import Testing
@testable import HealthMonitorCore

@Suite("HealthMonitorCore")
struct HealthAnalyticsCoreTests {
    @Test("Average handles values and empty input")
    func average() {
        #expect(HealthAnalytics.average([60, 70, 80]) == 70)
        #expect(HealthAnalytics.average([]) == nil)
    }

    @Test("Percent change")
    func percentChange() {
        #expect(HealthAnalytics.percentChange(new: 110, old: 100) == 10)
        #expect(HealthAnalytics.percentChange(new: 100, old: 0) == nil)
        #expect(HealthAnalytics.percentChange(new: nil, old: 100) == nil)
    }

    @Test("Orthostatic analysis")
    func orthostatic() {
        let result = HealthAnalytics.orthostaticAnalysis(
            baselineSamples: [68, 70, 72],
            standingSamples: [80, 92, 88],
            finalStandingSamples: [84, 86]
        )

        #expect(result.baselineHeartRate == 70)
        #expect(result.peakStandingHeartRate == 92)
        #expect(result.finalStandingHeartRate == 85)
        #expect(result.peakDelta == 22)
        #expect(result.finalDelta == 15)
    }

    @Test("Missing orthostatic samples do not invent values")
    func missingSamples() {
        let result = HealthAnalytics.orthostaticAnalysis(
            baselineSamples: [],
            standingSamples: [],
            finalStandingSamples: []
        )

        #expect(result.baselineHeartRate == nil)
        #expect(result.peakStandingHeartRate == nil)
        #expect(result.finalStandingHeartRate == nil)
        #expect(result.peakDelta == nil)
        #expect(result.finalDelta == nil)
    }

    @Test("CSV formula injection is neutralized")
    func csvSanitizer() {
        #expect(
            CSVSanitizer.protectSpreadsheetFormula("=SUM(A1:A2)")
                == "'=SUM(A1:A2)"
        )
        #expect(
            CSVSanitizer.protectSpreadsheetFormula(" \t@cmd")
                == "' \t@cmd"
        )
        #expect(
            CSVSanitizer.protectSpreadsheetFormula("\u{FEFF}+CMD")
                == "'\u{FEFF}+CMD"
        )
        #expect(
            CSVSanitizer.protectSpreadsheetFormula("\r=1+1")
                == "'\r=1+1"
        )
        #expect(CSVSanitizer.protectSpreadsheetFormula("-12.5") == "-12.5")
        #expect(CSVSanitizer.escape("hello,world") == "\"hello,world\"")
    }

    @Test("Heart-rate freshness honors exact boundary")
    func heartRateFreshness() {
        let now = Date(timeIntervalSince1970: 10_000)

        #expect(
            DataFreshness.isFresh(
                timestamp: now.addingTimeInterval(-600),
                now: now,
                maximumAge: 600
            )
        )
        #expect(
            !DataFreshness.isFresh(
                timestamp: now.addingTimeInterval(-601),
                now: now,
                maximumAge: 600
            )
        )
        #expect(
            !DataFreshness.isFresh(
                timestamp: now.addingTimeInterval(1),
                now: now,
                maximumAge: 600
            )
        )
    }

    @Test("User backup validates and round-trips")
    func backupRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let envelope = validEnvelope(now: now)

        _ = try envelope.validated(now: now)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(UserBackupEnvelope.self, from: data)

        #expect(restored.symptoms.first?.eventID == "symptom-1")
    }

    @Test("Backup rejects unsupported format")
    func backupRejectsUnsupportedFormat() {
        let now = Date(timeIntervalSince1970: 2_000)
        let base = validEnvelope(now: now)
        let bad = UserBackupEnvelope(
            formatVersion: 999,
            generatedAt: base.generatedAt,
            symptoms: base.symptoms,
            medications: base.medications,
            orthostaticSessions: base.orthostaticSessions
        )

        #expect(rejects(bad, now: now))
    }

    @Test("Backup rejects invalid symptom ranges")
    func backupRejectsInvalidSymptomRanges() {
        let now = Date(timeIntervalSince1970: 2_000)

        let lowHR = envelopeWithSymptom(
            now: now,
            severity: 5,
            heartRate: 19
        )
        let highHR = envelopeWithSymptom(
            now: now,
            severity: 5,
            heartRate: 301
        )
        let highSeverity = envelopeWithSymptom(
            now: now,
            severity: 11,
            heartRate: 88
        )

        #expect(rejects(lowHR, now: now))
        #expect(rejects(highHR, now: now))
        #expect(rejects(highSeverity, now: now))
    }

    @Test("Backup accepts heart-rate range boundaries")
    func backupAcceptsHeartRateBoundaries() throws {
        let now = Date(timeIntervalSince1970: 2_000)

        _ = try envelopeWithSymptom(
            now: now,
            severity: 0,
            heartRate: 20
        ).validated(now: now)

        _ = try envelopeWithSymptom(
            now: now,
            severity: 10,
            heartRate: 300
        ).validated(now: now)
    }

    @Test("Backup rejects clearly future timestamps")
    func backupRejectsFutureTimestamp() {
        let now = Date(timeIntervalSince1970: 100_000)
        let future = now.addingTimeInterval(24 * 60 * 60 + 1)

        let bad = UserBackupEnvelope(
            formatVersion: UserBackupEnvelope.currentFormatVersion,
            generatedAt: now,
            symptoms: [
                UserBackupSymptom(
                    eventID: "future",
                    timestamp: future,
                    symptom: "어지러움",
                    posture: "서 있음",
                    severity: 5,
                    heartRate: 88,
                    note: ""
                )
            ],
            medications: [],
            orthostaticSessions: []
        )

        #expect(rejects(bad, now: now))
    }

    @Test("Backup rejects invalid medication dose")
    func backupRejectsInvalidMedicationDose() {
        let now = Date(timeIntervalSince1970: 2_000)

        for dose in [-1.0, 1_000_001.0, Double.nan] {
            let bad = UserBackupEnvelope(
                formatVersion: UserBackupEnvelope.currentFormatVersion,
                generatedAt: now,
                symptoms: [],
                medications: [
                    UserBackupMedication(
                        eventID: "med",
                        timestamp: now,
                        name: "Test",
                        dose: dose,
                        unit: "mg",
                        note: ""
                    )
                ],
                orthostaticSessions: []
            )

            #expect(rejects(bad, now: now))
        }
    }

    @Test("Backup rejects invalid orthostatic values")
    func backupRejectsInvalidOrthostaticValues() {
        let now = Date(timeIntervalSince1970: 2_000)

        let longSession = UserBackupEnvelope(
            formatVersion: UserBackupEnvelope.currentFormatVersion,
            generatedAt: now,
            symptoms: [],
            medications: [],
            orthostaticSessions: [
                UserBackupOrthostatic(
                    eventID: "ortho-long",
                    timestamp: now,
                    baselineHeartRate: 70,
                    peakStandingHeartRate: 90,
                    finalStandingHeartRate: 85,
                    peakDelta: 20,
                    finalDelta: 15,
                    durationSeconds: 3_601,
                    completed: true,
                    note: ""
                )
            ]
        )

        let badDelta = UserBackupEnvelope(
            formatVersion: UserBackupEnvelope.currentFormatVersion,
            generatedAt: now,
            symptoms: [],
            medications: [],
            orthostaticSessions: [
                UserBackupOrthostatic(
                    eventID: "ortho-delta",
                    timestamp: now,
                    baselineHeartRate: 70,
                    peakStandingHeartRate: 90,
                    finalStandingHeartRate: 85,
                    peakDelta: 251,
                    finalDelta: 15,
                    durationSeconds: 180,
                    completed: true,
                    note: ""
                )
            ]
        )

        #expect(rejects(longSession, now: now))
        #expect(rejects(badDelta, now: now))
    }

    private func validEnvelope(now: Date) -> UserBackupEnvelope {
        UserBackupEnvelope(
            formatVersion: UserBackupEnvelope.currentFormatVersion,
            generatedAt: now,
            symptoms: [
                UserBackupSymptom(
                    eventID: "symptom-1",
                    timestamp: now.addingTimeInterval(-100),
                    symptom: "어지러움",
                    posture: "서 있음",
                    severity: 5,
                    heartRate: 88,
                    note: ""
                )
            ],
            medications: [],
            orthostaticSessions: []
        )
    }

    private func envelopeWithSymptom(
        now: Date,
        severity: Int,
        heartRate: Double?
    ) -> UserBackupEnvelope {
        UserBackupEnvelope(
            formatVersion: UserBackupEnvelope.currentFormatVersion,
            generatedAt: now,
            symptoms: [
                UserBackupSymptom(
                    eventID: "symptom",
                    timestamp: now,
                    symptom: "어지러움",
                    posture: "서 있음",
                    severity: severity,
                    heartRate: heartRate,
                    note: ""
                )
            ],
            medications: [],
            orthostaticSessions: []
        )
    }

    private func rejects(
        _ envelope: UserBackupEnvelope,
        now: Date
    ) -> Bool {
        do {
            _ = try envelope.validated(now: now)
            return false
        } catch {
            return true
        }
    }
}
