import SwiftUI

struct ReportView: View {
    @State private var reportText = ""
    @State private var reportURL: URL?
    @State private var reportError: String?
    @State private var isGenerating = false

    var body: some View {
        NavigationStack {
            List {
                Section("7일 리포트") {
                    Button(
                        isGenerating
                            ? "생성 중…"
                            : "리포트 새로 생성"
                    ) {
                        regenerate()
                    }
                    .disabled(isGenerating)

                    if let reportURL {
                        ShareLink(item: reportURL) {
                            Label(
                                "의사에게 공유 / 파일 저장",
                                systemImage:
                                    "square.and.arrow.up"
                            )
                        }
                    }

                    if let reportError {
                        Text(reportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text(
                        "리포트 파일은 기기가 잠겨 있는 동안 읽을 수 없는 보호 등급으로 저장됩니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Text(reportText)
                        .font(
                            .system(
                                .caption,
                                design: .monospaced
                            )
                        )
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("리포트")
            .onAppear {
                regenerate()
            }
        }
    }

    private func regenerate() {
        guard !isGenerating else { return }

        isGenerating = true
        reportError = nil

        DispatchQueue.global(qos: .utility).async {
            let text = DatabaseManager.shared.reportText()

            let fm = FileManager.default
            let directory =
                AppPaths.protectedDataDirectory
                    .appendingPathComponent(
                        "Reports",
                        isDirectory: true
                    )

            let url =
                directory
                    .appendingPathComponent(
                        "HealthMonitor_7day_report.txt"
                    )

            do {
                try fm.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [
                        .protectionKey:
                            FileProtectionType.complete
                    ]
                )

                let data = Data(text.utf8)
                try data.write(
                    to: url,
                    options: [
                        .atomic,
                        .completeFileProtection
                    ]
                )

                SensitiveFileProtection
                    .protectRecursively(
                        directory
                    )

                DispatchQueue.main.async {
                    reportText = text
                    reportURL = url
                    isGenerating = false
                }
            } catch {
                AppLogger.shared.error(
                    "Report write failed: \(error.localizedDescription)"
                )

                DispatchQueue.main.async {
                    reportText = text
                    reportURL = nil
                    reportError =
                        error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }
}
