import SwiftUI
import UniformTypeIdentifiers

struct UserBackupView: View {
    @State private var backupURL: URL?
    @State private var statusText: String?
    @State private var errorText: String?
    @State private var isWorking = false
    @State private var showImporter = false

    var body: some View {
        Form {
            Section("백업 범위") {
                Text(
                    "증상 기록, 약 변경 기록, 기립 체크 기록만 JSON으로 백업합니다. Apple Health 원본 데이터와 앱의 HealthKit 캐시는 포함하지 않으며, 필요하면 Apple Health에서 다시 동기화합니다."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("백업") {
                Button(
                    isWorking
                        ? "처리 중…"
                        : "사용자 기록 백업 생성"
                ) {
                    createBackup()
                }
                .disabled(isWorking)

                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label(
                            "백업 파일 공유/저장",
                            systemImage:
                                "square.and.arrow.up"
                        )
                    }
                }
            }

            Section("복원") {
                Button("JSON 백업 파일 선택") {
                    showImporter = true
                }
                .disabled(isWorking)

                Text(
                    "같은 event_id의 기록은 중복 저장하지 않습니다. 기존 기록을 삭제하지 않고 누락된 기록만 합칩니다."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let statusText {
                Section("결과") {
                    Text(statusText)
                }
            }

            if let errorText {
                Section("오류") {
                    Text(errorText)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("기록 백업/복원")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }
                importBackup(url)
            case .failure(let error):
                errorText = error.localizedDescription
            }
        }
    }

    private func createBackup() {
        isWorking = true
        errorText = nil

        DispatchQueue.global(qos: .utility).async {
            do {
                let url = try BackupManager.shared
                    .createUserBackupFile()

                DispatchQueue.main.async {
                    backupURL = url
                    statusText = "사용자 기록 백업을 생성했습니다."
                    isWorking = false
                }
            } catch {
                DispatchQueue.main.async {
                    backupURL = nil
                    errorText = error.localizedDescription
                    isWorking = false
                }
            }
        }
    }

    private func importBackup(_ url: URL) {
        isWorking = true
        errorText = nil

        DispatchQueue.global(qos: .utility).async {
            do {
                let summary = try BackupManager.shared
                    .importUserBackup(from: url)

                DispatchQueue.main.async {
                    statusText =
                        "복원 완료 · 새로 추가된 기록 \(summary.insertedTotal)개 "
                        + "(증상 \(summary.insertedSymptoms), 약 \(summary.insertedMedications), 기립 \(summary.insertedOrthostaticSessions))"
                    isWorking = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorText = error.localizedDescription
                    isWorking = false
                }
            }
        }
    }
}
