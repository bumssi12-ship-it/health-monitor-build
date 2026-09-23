import SwiftUI
import WatchKit

struct OrthostaticCheckView: View {
    @EnvironmentObject private var heart: LiveHeartSessionManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(heart.phase.rawValue)
                    .font(.headline)

                if heart.phase == .idle || heart.phase == .finished || heart.phase == .stopped || heart.phase == .failed {
                    Text("안전한 곳에서 누운 상태로 시작하세요. 60초 후 진동이 오면 천천히 일어납니다.")
                        .font(.caption2)
                        .multilineTextAlignment(.center)

                    Button("측정 시작") {
                        heart.startOrthostaticCheck()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("\(heart.remainingSeconds)초")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    Text(heart.currentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "-- bpm")
                        .font(.title3)
                        .monospacedDigit()

                    if heart.phase == .supine {
                        Text("편하게 누워 있으세요.")
                            .font(.caption)
                    } else if heart.phase == .standing {
                        Text("천천히 선 상태를 유지하세요.")
                            .font(.caption)
                    }

                    Button("어지러워서 중단") {
                        heart.stopEarly(reason: "증상으로 사용자 중단")
                        WKInterfaceDevice.current().play(.failure)
                    }
                    .tint(.red)
                }

                if let result = heart.lastResult {
                    Divider()
                    resultRow("기준", result.baselineHeartRate)
                    resultRow("기립 최고", result.peakStandingHeartRate)
                    resultRow("마지막", result.finalStandingHeartRate)

                    if let delta = result.peakDelta {
                        Text("최고 변화 \(String(format: "%+.0f", delta)) bpm")
                            .font(.caption)
                    }
                }

                Text("진단용 검사가 아닙니다. 심한 어지럼, 실신 느낌, 흉통 또는 호흡곤란이 있으면 즉시 중단하세요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("기립 체크")
    }

    private func resultRow(_ title: String, _ value: Double?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.map { "\(Int($0.rounded())) bpm" } ?? "-")
                .monospacedDigit()
        }
        .font(.caption)
    }
}
