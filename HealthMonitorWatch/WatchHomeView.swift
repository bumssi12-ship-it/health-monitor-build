import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject
    private var heart:
        LiveHeartSessionManager

    @EnvironmentObject
    private var connectivity:
        WatchConnectivityManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(
                        spacing: 3
                    ) {
                        Text(
                            "최근 측정 심박"
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )

                        Text(
                            heart
                                .currentHeartRate
                                .map {
                                    "\(Int($0.rounded()))"
                                }
                            ?? "--"
                        )
                        .font(
                            .system(
                                size: 34,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()

                        Text("bpm")
                            .font(.caption2)
                    }
                    .frame(
                        maxWidth:
                            .infinity
                    )
                }

                NavigationLink(
                    "증상 기록"
                ) {
                    QuickSymptomView()
                }

                NavigationLink(
                    "3분 기립 체크"
                ) {
                    OrthostaticCheckView()
                }

                if connectivity
                    .pendingTransfers
                    > 0 {
                    VStack(
                        alignment:
                            .leading,
                        spacing: 4
                    ) {
                        Text(
                            "전송 대기 \(connectivity.pendingTransfers)건"
                        )
                        .font(.caption2)
                        .foregroundStyle(
                            .secondary
                        )

                        Button(
                            "지금 다시 전송"
                        ) {
                            connectivity
                                .retryPendingNow()
                        }
                        .font(.caption2)
                    }
                }

                if let error =
                    connectivity
                        .lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if let error =
                    heart
                        .errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Health")
        }
    }
}
