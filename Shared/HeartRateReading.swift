import Foundation

struct HeartRateReading {
    let value: Double
    let timestamp: Date
}

enum DataFreshness {
    static func isFresh(
        timestamp: Date,
        now: Date = Date(),
        maximumAge: TimeInterval
    ) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= 0 && age <= maximumAge
    }
}
