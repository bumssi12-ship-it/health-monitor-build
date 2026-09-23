import Foundation

final class PendingWatchEventStore {
    static let shared =
        PendingWatchEventStore()

    private enum StoreError:
        LocalizedError {
        case invalidPayload
        case corruptStore

        var errorDescription: String? {
            switch self {
            case .invalidPayload:
                return "전송 대기 데이터 형식이 올바르지 않습니다."
            case .corruptStore:
                return "전송 대기 저장소를 읽을 수 없습니다."
            }
        }
    }

    private let queue =
        DispatchQueue(
            label:
                "HealthMonitorWatch.PendingEvents"
        )

    private let fileURL: URL
    private var lastErrorText: String?

    private init() {
        let fm =
            FileManager.default

        let base =
            fm.urls(
                for:
                    .applicationSupportDirectory,
                in:
                    .userDomainMask
            )[0]

        var directory =
            base.appendingPathComponent(
                "HealthMonitorWatchData",
                isDirectory: true
            )

        try? fm.createDirectory(
            at: directory,
            withIntermediateDirectories:
                true,
            attributes: [
                .protectionKey:
                    FileProtectionType
                        .completeUntilFirstUserAuthentication
            ]
        )

        try? fm.setAttributes(
            [
                .protectionKey:
                    FileProtectionType
                        .completeUntilFirstUserAuthentication
            ],
            ofItemAtPath:
                directory.path
        )

        var values =
            URLResourceValues()

        values
            .isExcludedFromBackup =
            true

        try?
            directory
                .setResourceValues(
                    values
                )

        fileURL =
            directory
                .appendingPathComponent(
                    "pending-events.plist"
                )
    }

    @discardableResult
    func enqueue(
        _ payload:
            [String: Any]
    ) -> Bool {
        queue.sync {
            guard let eventID =
                payload[
                    "event_id"
                ] as? String,
                !eventID.isEmpty
            else {
                lastErrorText =
                    StoreError
                        .invalidPayload
                        .localizedDescription
                return false
            }

            do {
                var events =
                    try loadUnsafe()

                if events.contains(
                    where: {
                        (
                            $0[
                                "event_id"
                            ] as? String
                        )
                        == eventID
                    }
                ) {
                    lastErrorText =
                        nil
                    return true
                }

                events.append(
                    payload
                )

                try saveUnsafe(
                    events
                )

                lastErrorText =
                    nil
                return true
            } catch {
                lastErrorText =
                    error
                        .localizedDescription
                return false
            }
        }
    }

    @discardableResult
    func remove(
        eventID: String
    ) -> Bool {
        queue.sync {
            do {
                let events =
                    try loadUnsafe()

                let filtered =
                    events.filter {
                        (
                            $0[
                                "event_id"
                            ] as? String
                        )
                        != eventID
                    }

                try saveUnsafe(
                    filtered
                )

                lastErrorText =
                    nil
                return true
            } catch {
                lastErrorText =
                    error
                        .localizedDescription
                return false
            }
        }
    }

    func all() -> [[String: Any]] {
        queue.sync {
            do {
                let events =
                    try loadUnsafe()

                lastErrorText =
                    nil
                return events
            } catch {
                lastErrorText =
                    error
                        .localizedDescription
                return []
            }
        }
    }

    func count() -> Int {
        queue.sync {
            do {
                let value =
                    try loadUnsafe()
                        .count

                lastErrorText =
                    nil
                return value
            } catch {
                lastErrorText =
                    error
                        .localizedDescription
                return 0
            }
        }
    }

    func storageError() -> String? {
        queue.sync {
            lastErrorText
        }
    }

    private func loadUnsafe()
        throws
        -> [[String: Any]] {
        let fm =
            FileManager.default

        guard
            fm.fileExists(
                atPath:
                    fileURL.path
            )
        else {
            return []
        }

        let data =
            try Data(
                contentsOf:
                    fileURL
            )

        let object =
            try PropertyListSerialization
                .propertyList(
                    from: data,
                    options: [],
                    format: nil
                )

        guard let events =
            object
            as? [[String: Any]]
        else {
            throw
                StoreError
                    .corruptStore
        }

        return events
    }

    private func saveUnsafe(
        _ events:
            [[String: Any]]
    ) throws {
        let data =
            try PropertyListSerialization
                .data(
                    fromPropertyList:
                        events,
                    format: .binary,
                    options: 0
                )

        try data.write(
            to: fileURL,
            options: .atomic
        )

        try?
            FileManager.default
                .setAttributes(
                    [
                        .protectionKey:
                            FileProtectionType
                                .completeUntilFirstUserAuthentication
                    ],
                    ofItemAtPath:
                        fileURL.path
                )

        var url =
            fileURL

        var values =
            URLResourceValues()

        values
            .isExcludedFromBackup =
            true

        try?
            url.setResourceValues(
                values
            )
    }
}
