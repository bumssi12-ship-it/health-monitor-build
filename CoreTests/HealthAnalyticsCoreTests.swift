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
        #expect(CSVSanitizer.protectSpreadsheetFormula("-12.5") == "-12.5")
        #expect(CSVSanitizer.escape("hello,world") == "\"hello,world\"")
    }

    @Test("Heart-rate freshness rejects old or future readings")
    func heartRateFreshness() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(
            DataFreshness.isFresh(
                timestamp: now.addingTimeInterval(-599),
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
        let envelope = UserBackupEnvelope(
            formatVersion: UserBackupEnvelope.currentFormatVersion,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            symptoms: [
                UserBackupSymptom(
                    eventID: "symptom-1",
                    timestamp: Date(timeIntervalSince1970: 900),
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

        _ = try envelope.validated()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(UserBackupEnvelope.self, from: data)

        #expect(restored.symptoms.first?.eventID == "symptom-1")
    }
}
