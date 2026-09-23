import Testing
@testable import HealthMonitor

@Suite("HealthAnalytics")
struct HealthAnalyticsTests {
    @Test("average calculates arithmetic mean")
    func average() {
        #expect(HealthAnalytics.average([60, 70, 80]) == 70)
        #expect(HealthAnalytics.average([]) == nil)
    }

    @Test("percent change handles normal and zero baseline")
    func percentChange() {
        #expect(HealthAnalytics.percentChange(new: 110, old: 100) == 10)
        #expect(HealthAnalytics.percentChange(new: 100, old: 0) == nil)
        #expect(HealthAnalytics.percentChange(new: nil, old: 100) == nil)
    }

    @Test("delta computes change from baseline")
    func delta() {
        #expect(HealthAnalytics.delta(95, baseline: 70) == 25)
        #expect(HealthAnalytics.delta(nil, baseline: 70) == nil)
    }

    @Test("orthostatic summary uses baseline mean, standing peak, final mean")
    func orthostaticSummary() {
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

    @Test("orthostatic summary safely handles missing samples")
    func orthostaticMissingSamples() {
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
}
