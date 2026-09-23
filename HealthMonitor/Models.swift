import Foundation

enum HealthMetric: String, CaseIterable, Identifiable, Codable {
    case heartRate = "heart_rate"
    case restingHeartRate = "resting_heart_rate"
    case walkingHeartRate = "walking_heart_rate"
    case hrv = "hrv_sdnn"
    case respiratoryRate = "respiratory_rate"
    case stepCount = "step_count"
    case sleep = "sleep"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting HR"
        case .walkingHeartRate: return "Walking HR"
        case .hrv: return "HRV (SDNN)"
        case .respiratoryRate: return "Respiratory Rate"
        case .stepCount: return "Steps"
        case .sleep: return "Sleep"
        }
    }
}

struct DashboardSnapshot {
    var latestHeartRate: Double?
    var latestHeartRateAt: Date?
    var restingHeartRate: Double?
    var restingHeartRateAt: Date?
    var latestHRV: Double?
    var latestHRVAt: Date?
    var respiratoryRate: Double?
    var respiratoryRateAt: Date?
    var todaySteps: Double?
    var lastSleepHours: Double?
    var last7DaySymptoms: Int
    var hrvChangePercent: Double?
    var restingHRChangePercent: Double?
    var sleepChangePercent: Double?
    var stepsChangePercent: Double?
}

struct SymptomRecord: Identifiable, Codable {
    let id: Int64
    let eventID: String?
    let timestamp: Date
    let symptom: String
    let posture: String
    let severity: Int
    let heartRate: Double?
    let note: String
}

struct MedicationRecord: Identifiable, Codable {
    let id: Int64
    let eventID: String?
    let timestamp: Date
    let name: String
    let dose: Double?
    let unit: String
    let note: String
}

struct OrthostaticRecord: Identifiable, Codable {
    let id: Int64
    let eventID: String?
    let timestamp: Date
    let baselineHeartRate: Double?
    let peakStandingHeartRate: Double?
    let finalStandingHeartRate: Double?
    let peakDelta: Double?
    let finalDelta: Double?
    let durationSeconds: Int
    let completed: Bool
    let note: String
}

struct DiagnosticStatus {
    let databasePath: String
    let databaseUserVersion: Int
    let healthAnchorsStored: Int
    let pendingWatchTransfers: Int?
    let lastHealthSyncAt: Date?
    let logPath: String
}

enum SymptomKind: String, CaseIterable, Identifiable {
    case dizziness = "어지러움"
    case fatigue = "심한 피로"
    case palpitations = "두근거림"
    case anxiety = "불안/공황 느낌"
    case headache = "두통"
    case other = "기타"

    var id: String { rawValue }
}

enum PostureKind: String, CaseIterable, Identifiable {
    case lying = "누워 있음"
    case sitting = "앉아 있음"
    case standing = "서 있음"
    case unknown = "미상"

    var id: String { rawValue }
}


struct MedicationComparison {
    let medication: MedicationRecord

    let beforeRestingHR: Double?
    let afterRestingHR: Double?
    let beforeRestingHRDays: Int
    let afterRestingHRDays: Int

    let beforeHRV: Double?
    let afterHRV: Double?
    let beforeHRVDays: Int
    let afterHRVDays: Int

    let beforeSleepHoursPerDay: Double?
    let afterSleepHoursPerDay: Double?
    let beforeSleepNights: Int
    let afterSleepNights: Int

    let beforeStepsPerDay: Double?
    let afterStepsPerDay: Double?
    let beforeStepDays: Int
    let afterStepDays: Int

    let beforeWindowDays: Int
    let afterWindowDays: Int
}


struct HealthSampleRecord {
    let uuid: String
    let type: HealthMetric
    let start: Date
    let end: Date
    let value: Double
    let unit: String
    let source: String
}

struct DailyMetricRecord {
    let dayStart: Date
    let type: HealthMetric
    let value: Double
    let unit: String
}


struct LatestMetricRecord {
    let value: Double
    let timestamp: Date
}
