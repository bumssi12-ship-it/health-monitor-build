import Foundation

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(
        label: "HealthMonitor.Logger",
        qos: .utility
    )
    private let maxBytes: UInt64 = 1_000_000

    let logURL: URL

    private init() {
        let fm = FileManager.default
        let base = AppPaths.protectedDataDirectory
        let logDir = base.appendingPathComponent(
            "Logs",
            isDirectory: true
        )

        try? fm.createDirectory(
            at: logDir,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey:
                    FileProtectionType
                        .completeUntilFirstUserAuthentication
            ]
        )

        logURL = logDir.appendingPathComponent(
            "health_monitor.log"
        )
        applyProtection(to: logURL)
    }

    func info(_ message: String) {
        append(level: "INFO", message: message)
    }

    func warning(_ message: String) {
        append(level: "WARN", message: message)
    }

    func error(_ message: String) {
        append(level: "ERROR", message: message)
    }

    private func append(
        level: String,
        message: String
    ) {
        queue.async {
            self.rotateIfNeeded()

            let formatter = ISO8601DateFormatter()
            let line =
                "\(formatter.string(from: Date())) [\(level)] \(message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(
                atPath: self.logURL.path
            ) {
                do {
                    let handle = try FileHandle(
                        forWritingTo: self.logURL
                    )
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } catch {
                    print(
                        "Logger write failed: \(error.localizedDescription)"
                    )
                }
            } else {
                do {
                    try data.write(
                        to: self.logURL,
                        options: .atomic
                    )
                    self.applyProtection(
                        to: self.logURL
                    )
                } catch {
                    print(
                        "Logger create failed: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    private func rotateIfNeeded() {
        guard FileManager.default.fileExists(
            atPath: logURL.path
        ) else {
            return
        }

        do {
            let handle = try FileHandle(
                forReadingFrom: logURL
            )
            let size = try handle.seekToEnd()
            try handle.close()

            guard size >= maxBytes else {
                return
            }
        } catch {
            return
        }

        let rotated = logURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "health_monitor.log.1"
            )

        try? FileManager.default.removeItem(
            at: rotated
        )
        try? FileManager.default.moveItem(
            at: logURL,
            to: rotated
        )
        applyProtection(to: rotated)
    }

    private func applyProtection(
        to url: URL
    ) {
        guard FileManager.default.fileExists(
            atPath: url.path
        ) else {
            return
        }

        try? FileManager.default.setAttributes(
            [
                .protectionKey:
                    FileProtectionType
                        .completeUntilFirstUserAuthentication
            ],
            ofItemAtPath: url.path
        )
    }
}
