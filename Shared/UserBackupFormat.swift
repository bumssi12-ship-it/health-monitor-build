import Foundation

struct UserBackupEnvelope: Codable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let generatedAt: Date
    let symptoms: [UserBackupSymptom]
    let medications: [UserBackupMedication]
    let orthostaticSessions: [UserBackupOrthostatic]

    func validated(
        now: Date = Date()
    ) throws -> UserBackupEnvelope {
        guard formatVersion
            == Self.currentFormatVersion else {
            throw UserBackupValidationError
                .unsupportedFormat(
                    formatVersion
                )
        }

        let total =
            symptoms.count
            + medications.count
            + orthostaticSessions.count

        guard total <= 100_000 else {
            throw UserBackupValidationError
                .tooManyRecords(
                    total
                )
        }

        let earliestAllowed =
            Date(
                timeIntervalSince1970: 0
            )
        let latestAllowed =
            now.addingTimeInterval(
                24 * 60 * 60
            )

        try validateDate(
            generatedAt,
            earliest: earliestAllowed,
            latest: latestAllowed,
            field: "generatedAt"
        )

        for item in symptoms {
            try validateEventID(
                item.eventID
            )
            try validateDate(
                item.timestamp,
                earliest: earliestAllowed,
                latest: latestAllowed,
                field: "symptom timestamp"
            )

            guard
                (0...10)
                    .contains(
                        item.severity
                    )
            else {
                throw
                    UserBackupValidationError
                        .invalidRecord(
                            "symptom severity"
                        )
            }

            try validateOptionalHeartRate(
                item.heartRate,
                field:
                    "symptom heart rate"
            )

            try validateText(
                item.symptom,
                field: "symptom",
                max: 200
            )
            try validateText(
                item.posture,
                field: "posture",
                max: 100
            )
            try validateText(
                item.note,
                field: "symptom note",
                max: 4_000
            )
        }

        for item in medications {
            try validateEventID(
                item.eventID
            )
            try validateDate(
                item.timestamp,
                earliest: earliestAllowed,
                latest: latestAllowed,
                field:
                    "medication timestamp"
            )

            if let dose = item.dose {
                guard
                    dose.isFinite,
                    dose >= 0,
                    dose <= 1_000_000
                else {
                    throw
                        UserBackupValidationError
                            .invalidRecord(
                                "medication dose"
                            )
                }
            }

            try validateText(
                item.name,
                field:
                    "medication name",
                max: 300
            )
            try validateText(
                item.unit,
                field:
                    "medication unit",
                max: 50
            )
            try validateText(
                item.note,
                field:
                    "medication note",
                max: 4_000
            )
        }

        for item in orthostaticSessions {
            try validateEventID(
                item.eventID
            )
            try validateDate(
                item.timestamp,
                earliest: earliestAllowed,
                latest: latestAllowed,
                field:
                    "orthostatic timestamp"
            )

            guard
                item.durationSeconds
                    >= 0,
                item.durationSeconds
                    <= 3_600
            else {
                throw
                    UserBackupValidationError
                        .invalidRecord(
                            "orthostatic duration"
                        )
            }

            try validateOptionalHeartRate(
                item.baselineHeartRate,
                field:
                    "orthostatic baseline"
            )
            try validateOptionalHeartRate(
                item.peakStandingHeartRate,
                field:
                    "orthostatic peak"
            )
            try validateOptionalHeartRate(
                item.finalStandingHeartRate,
                field:
                    "orthostatic final"
            )
            try validateOptionalDelta(
                item.peakDelta,
                field:
                    "orthostatic peak delta"
            )
            try validateOptionalDelta(
                item.finalDelta,
                field:
                    "orthostatic final delta"
            )

            try validateText(
                item.note,
                field:
                    "orthostatic note",
                max: 4_000
            )
        }

        return self
    }

    private func validateEventID(
        _ eventID: String
    ) throws {
        try validateText(
            eventID,
            field: "event id",
            max: 200
        )

        guard
            !eventID
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty
        else {
            throw
                UserBackupValidationError
                    .invalidRecord(
                        "empty event id"
                    )
        }
    }

    private func validateDate(
        _ date: Date,
        earliest: Date,
        latest: Date,
        field: String
    ) throws {
        guard
            date >= earliest,
            date <= latest
        else {
            throw
                UserBackupValidationError
                    .invalidRecord(
                        field
                    )
        }
    }

    private func validateOptionalHeartRate(
        _ value: Double?,
        field: String
    ) throws {
        guard let value else {
            return
        }

        guard
            value.isFinite,
            value >= 20,
            value <= 300
        else {
            throw
                UserBackupValidationError
                    .invalidRecord(
                        field
                    )
        }
    }

    private func validateOptionalDelta(
        _ value: Double?,
        field: String
    ) throws {
        guard let value else {
            return
        }

        guard
            value.isFinite,
            value >= -250,
            value <= 250
        else {
            throw
                UserBackupValidationError
                    .invalidRecord(
                        field
                    )
        }
    }

    private func validateText(
        _ text: String,
        field: String,
        max: Int
    ) throws {
        guard
            text.utf8.count <= max
        else {
            throw
                UserBackupValidationError
                    .textTooLong(
                        field
                    )
        }
    }
}

struct UserBackupSymptom: Codable {
    let eventID: String
    let timestamp: Date
    let symptom: String
    let posture: String
    let severity: Int
    let heartRate: Double?
    let note: String
}

struct UserBackupMedication: Codable {
    let eventID: String
    let timestamp: Date
    let name: String
    let dose: Double?
    let unit: String
    let note: String
}

struct UserBackupOrthostatic: Codable {
    let eventID: String
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

struct UserBackupImportSummary {
    let insertedSymptoms: Int
    let insertedMedications: Int
    let insertedOrthostaticSessions: Int

    var insertedTotal: Int {
        insertedSymptoms
            + insertedMedications
            + insertedOrthostaticSessions
    }
}

enum UserBackupValidationError:
    LocalizedError {

    case unsupportedFormat(Int)
    case tooManyRecords(Int)
    case invalidRecord(String)
    case textTooLong(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(
            let version
        ):
            return
                "지원하지 않는 백업 형식입니다. 버전: \(version)"

        case .tooManyRecords(
            let count
        ):
            return
                "백업 기록 수가 너무 많습니다: \(count)"

        case .invalidRecord(
            let field
        ):
            return
                "백업 데이터가 올바르지 않습니다: \(field)"

        case .textTooLong(
            let field
        ):
            return
                "백업 텍스트가 너무 깁니다: \(field)"
        }
    }
}
