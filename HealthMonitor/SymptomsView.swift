import SwiftUI

struct SymptomsView: View {
    @EnvironmentObject private var health: HealthKitManager

    @State private var selectedSymptom: SymptomKind = .dizziness
    @State private var selectedPosture: PostureKind = .lying
    @State private var severity: Double = 5
    @State private var note = ""
    @State private var rows: [SymptomRecord] = []
    @State private var savedMessage: String?
    @State private var isSaving = false

    private let heartRateMaximumAge: TimeInterval = 10 * 60

    var body: some View {
        NavigationStack {
            Form {
                Section("지금 증상 기록") {
                    Picker("증상", selection: $selectedSymptom) {
                        ForEach(SymptomKind.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }

                    Picker("자세", selection: $selectedPosture) {
                        ForEach(
                            PostureKind.allCases.filter {
                                $0 != .unknown
                            }
                        ) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }

                    VStack(alignment: .leading) {
                        Text("강도 \(Int(severity))/10")
                        Slider(
                            value: $severity,
                            in: 0...10,
                            step: 1
                        )
                    }

                    TextField(
                        "메모 (선택)",
                        text: $note,
                        axis: .vertical
                    )

                    Button(
                        isSaving
                            ? "저장 중…"
                            : "최근 심박과 함께 저장"
                    ) {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)

                    Text(
                        "심박은 기록 시점 기준 10분 이내 HealthKit 샘플만 자동 첨부합니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let savedMessage {
                        Text(savedMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("최근 기록") {
                    if rows.isEmpty {
                        Text("아직 기록이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { item in
                            VStack(
                                alignment: .leading,
                                spacing: 4
                            ) {
                                HStack {
                                    Text(item.symptom)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(item.severity)/10")
                                        .monospacedDigit()
                                }

                                Text(
                                    "\(item.posture) · \(item.timestamp.formatted(date: .abbreviated, time: .shortened))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                if let hr = item.heartRate {
                                    Text(
                                        "HR \(String(format: "%.0f", hr)) bpm"
                                    )
                                    .font(.caption)
                                }

                                if !item.note.isEmpty {
                                    Text(item.note)
                                        .font(.subheadline)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .navigationTitle("증상")
            .onAppear {
                reload()
            }
        }
    }

    private func save() {
        isSaving = true
        savedMessage = nil

        health.fetchLatestHeartRateReading { reading in
            let now = Date()
            let freshReading: HeartRateReading?

            if let reading,
               DataFreshness.isFresh(
                    timestamp: reading.timestamp,
                    now: now,
                    maximumAge: heartRateMaximumAge
               ) {
                freshReading = reading
            } else {
                freshReading = nil
            }

            let trimmedNote = note
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

            DatabaseManager.shared.addSymptom(
                symptom: selectedSymptom.rawValue,
                posture: selectedPosture.rawValue,
                severity: Int(severity),
                heartRate: freshReading?.value,
                note: trimmedNote
            ) { success in
                isSaving = false

                guard success else {
                    savedMessage =
                        "저장에 실패했습니다. 다시 시도하세요."
                    return
                }

                if let freshReading {
                    let relative =
                        RelativeDateTimeFormatter()
                            .localizedString(
                                for:
                                    freshReading.timestamp,
                                relativeTo:
                                    now
                            )
                    savedMessage =
                        "저장됨 · 심박 \(String(format: "%.0f", freshReading.value)) bpm (\(relative))"
                } else if reading != nil {
                    savedMessage =
                        "저장됨 · 마지막 심박 샘플이 10분보다 오래되어 첨부하지 않았습니다."
                } else {
                    savedMessage =
                        "저장됨 · 사용할 수 있는 심박 샘플이 없습니다."
                }

                note = ""
                reload()
            }
        }
    }

    private func reload() {
        rows = DatabaseManager.shared
            .recentSymptoms()
    }
}
