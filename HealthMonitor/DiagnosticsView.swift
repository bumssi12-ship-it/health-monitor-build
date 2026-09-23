import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject
    private var health:
        HealthKitManager

    @State
    private var exportURLs:
        [URL] = []

    @State
    private var exportError:
        String?

    @State
    private var status:
        DiagnosticStatus?

    @State
    private var dbCheckResult =
        "확인 전"

    @State
    private var isWorking =
        false

    @State
    private var showRebuildAlert =
        false

    @State
    private var quality:
        [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section(
                    "HealthKit"
                ) {
                    LabeledContent(
                        "권한 요청 상태"
                    ) {
                        Text(
                            health
                                .authorizationRequestStatusText
                        )
                    }

                    Text(
                        "HealthKit은 읽기 권한의 실제 허용/거부 여부를 앱에 직접 공개하지 않습니다. 데이터가 조회되는지로만 간접 확인합니다."
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                    Button(
                        "권한 요청 상태 새로 확인"
                    ) {
                        health
                            .refreshAuthorizationRequestStatus()
                    }
                }

                Section(
                    "데이터 품질"
                ) {
                    qualityRow(
                        "최근 심박",
                        quality[
                            "heart"
                        ]
                    )
                    qualityRow(
                        "안정시 심박 7일",
                        quality[
                            "rhr"
                        ]
                    )
                    qualityRow(
                        "HRV 7일",
                        quality[
                            "hrv"
                        ]
                    )
                    qualityRow(
                        "수면 7일",
                        quality[
                            "sleep"
                        ]
                    )
                    qualityRow(
                        "걸음 7일",
                        quality[
                            "steps"
                        ]
                    )
                }

                Section(
                    "동기화"
                ) {
                    LabeledContent(
                        "최근 Health 데이터 반영"
                    ) {
                        Text(
                            status?
                                .lastHealthSyncAt?
                                .formatted(
                                    date:
                                        .abbreviated,
                                    time:
                                        .shortened
                                )
                            ?? "-"
                        )
                    }

                    LabeledContent(
                        "저장된 Health anchor"
                    ) {
                        Text(
                            "\(status?.healthAnchorsStored ?? 0)"
                        )
                    }

                    LabeledContent(
                        "Watch ACK 전송 대기"
                    ) {
                        if let count =
                            status?
                                .pendingWatchTransfers {
                            Text(
                                "\(count)"
                            )
                        } else {
                            Text("-")
                        }
                    }

                    Button(
                        "지금 증분 동기화"
                    ) {
                        health
                            .syncAllIncremental()

                        DispatchQueue
                            .main
                            .asyncAfter(
                                deadline:
                                    .now()
                                    + 1.0
                            ) {
                                reload()
                            }
                    }

                    Button(
                        "Health 캐시 전체 재구축",
                        role:
                            .destructive
                    ) {
                        showRebuildAlert =
                            true
                    }
                    .disabled(
                        isWorking
                    )
                }

                Section(
                    "DB 무결성"
                ) {
                    LabeledContent(
                        "최근 검사"
                    ) {
                        Text(
                            dbCheckResult
                        )
                    }

                    Button(
                        "빠른 DB 검사"
                    ) {
                        runDBCheck(
                            full: false
                        )
                    }
                    .disabled(
                        isWorking
                    )

                    Button(
                        "전체 DB integrity 검사"
                    ) {
                        runDBCheck(
                            full: true
                        )
                    }
                    .disabled(
                        isWorking
                    )

                    Text(
                        "전체 검사는 DB가 커지면 시간이 더 걸릴 수 있습니다."
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )
                }

                Section(
                    "데이터"
                ) {
                    LabeledContent(
                        "DB schema"
                    ) {
                        Text(
                            "v\(status?.databaseUserVersion ?? 0)"
                        )
                    }

                    if let path =
                        status?
                            .databasePath {
                        Text(path)
                            .font(
                                .caption2
                            )
                            .foregroundStyle(
                                .secondary
                            )
                            .textSelection(
                                .enabled
                            )
                    }

                    Button(
                        isWorking
                            ? "처리 중…"
                            : "CSV/JSON 내보내기 생성"
                    ) {
                        createExport()
                    }
                    .disabled(
                        isWorking
                    )

                    if !exportURLs
                        .isEmpty {
                        ShareLink(
                            items:
                                exportURLs
                        ) {
                            Label(
                                "내보내기 파일 공유",
                                systemImage:
                                    "square.and.arrow.up"
                            )
                        }
                    }

                    if let exportError {
                        Text(
                            exportError
                        )
                        .font(.caption)
                        .foregroundStyle(
                            .red
                        )
                    }
                }

                Section(
                    "진단 로그"
                ) {
                    if let logPath =
                        status?
                            .logPath {
                        Text(
                            logPath
                        )
                        .font(
                            .caption2
                        )
                        .foregroundStyle(
                            .secondary
                        )
                        .textSelection(
                            .enabled
                        )
                    }
                }
            }
            .navigationTitle(
                "진단/내보내기"
            )
            .onAppear {
                health
                    .refreshAuthorizationRequestStatus()
                reload()
            }
            .refreshable {
                health
                    .refreshAuthorizationRequestStatus()
                reload()
            }
            .alert(
                "Health 캐시를 전체 재구축할까요?",
                isPresented:
                    $showRebuildAlert
            ) {
                Button(
                    "취소",
                    role:
                        .cancel
                ) {}

                Button(
                    "재구축",
                    role:
                        .destructive
                ) {
                    health
                        .resetAnchorsAndResync()

                    DispatchQueue
                        .main
                        .asyncAfter(
                            deadline:
                                .now()
                                + 1.0
                        ) {
                            reload()
                        }
                }
            } message: {
                Text(
                    "앱의 HealthKit 파생 캐시를 비운 뒤 원래의 최초 동기화 범위부터 다시 구성합니다. 증상·약 기록·기립 체크 기록은 삭제하지 않습니다."
                )
            }
        }
    }

    private func qualityRow(
        _ title: String,
        _ value: String?
    ) -> some View {
        LabeledContent(
            title
        ) {
            Text(
                value
                    ?? "-"
            )
        }
    }

    private func reload() {
        status =
            DiagnosticStatus(
                databasePath:
                    DatabaseManager
                        .shared
                        .databaseURL?
                        .path
                    ?? "-",
                databaseUserVersion:
                    DatabaseManager
                        .shared
                        .userVersion(),
                healthAnchorsStored:
                    health
                        .storedAnchorCount(),
                pendingWatchTransfers:
                    PhoneConnectivityManager
                        .shared
                        .pendingTransferCount(),
                lastHealthSyncAt:
                    health
                        .lastSyncAt,
                logPath:
                    AppLogger
                        .shared
                        .logURL
                        .path
            )

        reloadQuality()
    }

    private func reloadQuality() {
        let now =
            Date()

        let calendar =
            Calendar.current

        let today =
            calendar
                .startOfDay(
                    for: now
                )

        let start =
            calendar.date(
                byAdding: .day,
                value: -7,
                to: today
            )
            ?? today

        let db =
            DatabaseManager.shared

        let heart =
            db.latestSample(
                for: .heartRate
            )

        quality[
            "heart"
        ] =
            heart.map {
                RelativeDateTimeFormatter()
                    .localizedString(
                        for:
                            $0.timestamp,
                        relativeTo:
                            now
                    )
            }
            ?? "데이터 없음"

        quality[
            "rhr"
        ] =
            "\(db.recordedDayCount(for: .restingHeartRate, from: start, to: today))/7일"

        quality[
            "hrv"
        ] =
            "\(db.recordedDayCount(for: .hrv, from: start, to: today))/7일"

        quality[
            "sleep"
        ] =
            db
                .sleepSummary(
                    from: start,
                    to: today
                )
                .map {
                    "\($0.nights)/7일"
                }
            ?? "0/7일"

        quality[
            "steps"
        ] =
            "\(db.dailyMetricCoverageCount(for: .stepCount, from: start, to: today))/7일"
    }

    private func runDBCheck(
        full: Bool
    ) {
        isWorking =
            true

        dbCheckResult =
            "검사 중…"

        DispatchQueue
            .global(
                qos:
                    .utility
            )
            .async {
                let rows =
                    full
                    ? DatabaseManager
                        .shared
                        .integrityCheck()
                    : DatabaseManager
                        .shared
                        .quickCheck()

                let result =
                    rows == ["ok"]
                    ? (
                        full
                        ? "integrity_check PASS"
                        : "quick_check PASS"
                    )
                    : rows
                        .joined(
                            separator:
                                " / "
                        )

                DispatchQueue
                    .main
                    .async {
                        self
                            .dbCheckResult =
                            result
                        self
                            .isWorking =
                            false
                    }
            }
    }

    private func createExport() {
        isWorking =
            true
        exportError =
            nil

        DispatchQueue
            .global(
                qos:
                    .utility
            )
            .async {
                do {
                    let urls =
                        try ExportManager
                            .shared
                            .createExportBundle()

                    DispatchQueue
                        .main
                        .async {
                            self
                                .exportURLs =
                                urls
                            self
                                .isWorking =
                                false
                        }
                } catch {
                    DispatchQueue
                        .main
                        .async {
                            self
                                .exportURLs =
                                []
                            self
                                .exportError =
                                error
                                    .localizedDescription
                            self
                                .isWorking =
                                false

                            AppLogger
                                .shared
                                .error(
                                    "Export failed: "
                                    + error
                                        .localizedDescription
                                )
                        }
                }
            }
    }
}
