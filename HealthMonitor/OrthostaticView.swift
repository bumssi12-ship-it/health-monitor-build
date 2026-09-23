import SwiftUI

struct OrthostaticView: View {
    @State private var rows: [OrthostaticRecord] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Apple Watch에서 1분 누운 상태 + 3분 서 있는 상태의 심박 변화를 기록합니다. 진단 목적이 아니라 패턴 기록용입니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("최근 기록") {
                    if rows.isEmpty {
                        Text("아직 Watch 기립 체크 기록이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(item.completed ? "완료" : "중단")
                                        .font(.headline)
                                    Spacer()
                                    Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    value("기준", item.baselineHeartRate)
                                    value("최고", item.peakStandingHeartRate)
                                    value("마지막", item.finalStandingHeartRate)
                                }

                                if let peak = item.peakDelta {
                                    Text("기준 대비 최고 변화 \(String(format: "%+.0f", peak)) bpm")
                                        .font(.caption)
                                }

                                if !item.note.isEmpty {
                                    Text(item.note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .navigationTitle("기립 체크")
            .onAppear { reload() }
            .refreshable { reload() }
        }
    }

    private func value(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.map { "\(Int($0.rounded()))" } ?? "-")
                .font(.subheadline.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reload() {
        rows = DatabaseManager.shared.recentOrthostaticSessions()
    }
}
