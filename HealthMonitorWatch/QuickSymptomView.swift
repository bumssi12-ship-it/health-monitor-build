import SwiftUI
import WatchKit

struct QuickSymptomView: View {
    @EnvironmentObject
    private var heart:
        LiveHeartSessionManager

    @EnvironmentObject
    private var connectivity:
        WatchConnectivityManager

    @State
    private var posture =
        "누워 있음"

    @State
    private var severity =
        5

    @State
    private var savedText:
        String?

    private let postures = [
        "누워 있음",
        "앉아 있음",
        "서 있음"
    ]

    private let heartRateMaximumAge:
        TimeInterval =
        10 * 60

    var body: some View {
        ScrollView {
            VStack(
                spacing: 10
            ) {
                Picker(
                    "자세",
                    selection:
                        $posture
                ) {
                    ForEach(
                        postures,
                        id: \.self
                    ) { posture in
                        Text(posture)
                            .tag(posture)
                    }
                }

                Stepper(
                    "강도 \(severity)",
                    value:
                        $severity,
                    in: 0...10
                )

                symptomButton(
                    "어지러움"
                )
                symptomButton(
                    "심한 피로"
                )
                symptomButton(
                    "두근거림"
                )
                symptomButton(
                    "불안/공황 느낌"
                )

                if let savedText {
                    Text(
                        savedText
                    )
                    .font(
                        .caption2
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }
            }
        }
        .navigationTitle(
            "증상"
        )
    }

    private func symptomButton(
        _ symptom: String
    ) -> some View {
        Button(symptom) {
            heart
                .fetchLatestHeartRateEnsuringAuthorization {
                    reading in

                    let freshReading:
                        HeartRateReading?

                    if let reading,
                       DataFreshness
                        .isFresh(
                            timestamp:
                                reading
                                    .timestamp,
                            maximumAge:
                                heartRateMaximumAge
                        ) {
                        freshReading =
                            reading
                    } else {
                        freshReading =
                            nil
                    }

                    let persisted =
                        connectivity
                            .sendSymptom(
                                symptom:
                                    symptom,
                                posture:
                                    posture,
                                severity:
                                    severity,
                                heartRate:
                                    freshReading?
                                        .value
                            )

                    if persisted {
                        if let freshReading {
                            savedText =
                                "저장 대기 · \(Int(freshReading.value.rounded())) bpm"
                        } else if reading != nil {
                            savedText =
                                "저장 대기 · 심박 샘플이 오래되어 제외"
                        } else {
                            savedText =
                                "저장 대기 · 심박 없음"
                        }

                        WKInterfaceDevice
                            .current()
                            .play(
                                .success
                            )
                    } else {
                        savedText =
                            "로컬 전송 대기 저장 실패"

                        WKInterfaceDevice
                            .current()
                            .play(
                                .failure
                            )
                    }
                }
        }
        .buttonStyle(
            .borderedProminent
        )
    }
}
