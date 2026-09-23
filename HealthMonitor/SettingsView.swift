import SwiftUI

struct SettingsView: View {
    @AppStorage("privacy.appLockEnabled") private var appLockEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("개인정보 보호") {
                    Toggle("앱 잠금 사용", isOn: $appLockEnabled)

                    Text("켜면 앱을 다시 활성화할 때 Face ID, Touch ID 또는 기기 암호 인증을 요구합니다. HealthKit 백그라운드 수집 자체는 중단하지 않습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("백업/복원") {
                    NavigationLink("사용자 기록 백업/복원") {
                        UserBackupView()
                    }
                }

                Section("저장 정책") {
                    LabeledContent("건강 원본 데이터") {
                        Text("Apple Health")
                    }
                    LabeledContent("앱 분석 DB") {
                        Text("iPhone 로컬")
                    }
                    LabeledContent("클라우드 전송") {
                        Text("없음")
                    }
                }

                Section {
                    Text("이 앱은 의료기기나 진단 도구가 아닙니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("설정")
        }
    }
}
