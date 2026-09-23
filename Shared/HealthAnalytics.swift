import Foundation

struct OrthostaticAnalysisResult: Equatable {
    let baselineHeartRate: Double?
    let peakStandingHeartRate: Double?
    let finalStandingHeartRate: Double?
    let peakDelta: Double?
    let finalDelta: Double?
}

enum HealthAnalytics {
    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func percentChange(new: Double?, old: Double?) -> Double? {
        guard let new, let old, abs(old) > 0.0001 else { return nil }
        return ((new - old) / old) * 100.0
    }

    static func delta(_ value: Double?, baseline: Double?) -> Double? {
        guard let value, let baseline else { return nil }
        return value - baseline
    }

    static func orthostaticAnalysis(
        baselineSamples: [Double],
        standingSamples: [Double],
        finalStandingSamples: [Double]
    ) -> OrthostaticAnalysisResult {
        let baseline = average(baselineSamples)
        let peak = standingSamples.max()
        let final = average(finalStandingSamples)

        return OrthostaticAnalysisResult(
            baselineHeartRate: baseline,
            peakStandingHeartRate: peak,
            finalStandingHeartRate: final,
            peakDelta: delta(peak, baseline: baseline),
            finalDelta: delta(final, baseline: baseline)
        )
    }
}
