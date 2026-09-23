import Foundation

final class BackupManager {
    static let shared = BackupManager()

    private let maximumBackupBytes = 20 * 1024 * 1024

    private init() {}

    func createUserBackupFile() throws -> URL {
        let backup = try DatabaseManager.shared
            .makeUserBackup()
            .validated()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys
        ]

        let data = try encoder.encode(backup)

        guard data.count <= maximumBackupBytes else {
            throw BackupFileError.fileTooLarge
        }

        let fm = FileManager.default
        let directory = AppPaths.protectedDataDirectory
            .appendingPathComponent(
                "UserBackups",
                isDirectory: true
            )

        try fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey:
                    FileProtectionType.complete
            ]
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let url = directory.appendingPathComponent(
            "HealthMonitor-UserBackup-\(formatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).json"
        )

        try data.write(
            to: url,
            options: [
                .atomic,
                .completeFileProtection
            ]
        )

        SensitiveFileProtection.protect(url)

        cleanupOldBackups(
            in: directory,
            keep: 5
        )

        return url
    }

    func importUserBackup(
        from url: URL
    ) throws -> UserBackupImportSummary {
        let accessed =
            url.startAccessingSecurityScopedResource()

        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(
            contentsOf: url,
            options: [.mappedIfSafe]
        )

        guard data.count <= maximumBackupBytes else {
            throw BackupFileError.fileTooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backup = try decoder.decode(
            UserBackupEnvelope.self,
            from: data
        )

        return try DatabaseManager.shared
            .importUserBackup(
                backup.validated()
            )
    }

    private func cleanupOldBackups(
        in directory: URL,
        keep: Int
    ) {
        guard let urls = try? FileManager.default
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        let backups = urls
            .filter {
                $0.lastPathComponent
                    .hasPrefix(
                        "HealthMonitor-UserBackup-"
                    )
            }
            .sorted {
                $0.lastPathComponent
                    > $1.lastPathComponent
            }

        for old in backups.dropFirst(
            max(0, keep)
        ) {
            try? FileManager.default
                .removeItem(at: old)
        }
    }
}

enum BackupFileError: LocalizedError {
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "백업 파일이 허용 크기(20MB)를 초과했습니다."
        }
    }
}
