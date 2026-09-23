import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var health: HealthKitManager

    @State private var snapshot = DashboardSnapshot(
        latestHeartRate: nil,
        latestHeartRateAt: nil,
        restingHeartRate: nil,
        restingHeartRateAt: nil,
        latestHRV: nil,
        latestHRVAt: nil,
        respiratoryRate: nil,
        respiratoryRateAt: nil,
        todaySteps: nil,
        lastSleepHours: nil,
        last7DaySymptoms: 0,
        hrvChangePercent: nil,
        restingHRChangePercent: nil,
        sleepChangePercent: nil,
        stepsChangePercent: nil
    )

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    authorizationCard

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ],
                        spacing: 12
                    ) {
                        metricCard(
                            "최근 심박",
                            value(snapshot.latestHeartRate, "bpm"),
                            timestamp: snapshot.latestHeartRateAt
                        )
                        metricCard(
                            "안정시 심박",
                            value(snapshot.restingHeartRate, "bpm"),
                            timestamp: snapshot.restingHeartRateAt
                        )
                        metricCard(
                            "HRV",
                            value(snapshot.latestHRV, "ms"),
                            timestamp: snapshot.latestHRVAt
                        )
                        metricCard(
                            "호흡수",
                            value(snapshot.respiratoryRate, "/min"),
                            timestamp: snapshot.respiratoryRateAt
                        )
                        metricCard(
                            "오늘 걸음",
                            integer(snapshot.todaySteps),
                            timestamp: nil
                        )
                        metricCard(
                            "최근 수면",
                            sleepText(snapshot.lastSleepHours),
                            timestamp: nil
                        )
                    }

                    trendCard
                    safetyCard
                }
                .padding()
            }
            .navigationTitle("Health Monitor")
            .refreshable {
                health.syncAllIncremental()
                try? await Task.sleep(
                    nanoseconds: 700_000_000
                )
                reload()
            }
            .onAppear {
                reload()
            }
            .onReceive(health.$lastSyncAt) { _ in
                reload()
            }
        }
    }

    private var authorizationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apple Health 자동 연동")
                .font(.headline)

            Text(
                "심박수·HRV·수면·활동 데이터를 HealthKit에서 읽어 로컬 DB에 저장합니다."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Button("건강 데이터 접근 허용") {
                health.requestAuthorization { _ in
                    reload()
                }
            }
            .buttonStyle(.borderedProminent)

            if let lastSync = health.lastSyncAt {
                Text(
                    "최근 Health 데이터 반영: \(lastSync.formatted(date: .omitted, time: .shortened))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = health.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("완료된 최근 7일")
                .font(.headline)
            Text("증상 기록 \(snapshot.last7DaySymptoms)회")
            trendLine("HRV", snapshot.hrvChangePercent)
            trendLine(
                "안정시 심박",
                snapshot.restingHRChangePercent
            )
            trendLine("수면", snapshot.sleepChangePercent)
            trendLine("걸음", snapshot.stepsChangePercent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("해석 기준")
                .font(.headline)
            Text(
                "이 앱은 진단 도구가 아닙니다. 수치 변화와 증상 발생 시점을 기록해 진료 시 참고하기 위한 용도입니다."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func metricCard(
        _ title: String,
        _ value: String,
        timestamp: Date?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.bold())

            if let timestamp {
                Text(relativeTime(timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 86,
            alignment: .leading
        )
        .padding()
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    private func trendLine(
        _ title: String,
        _ percent: Double?
    ) -> some View {
        HStack {
            Text(title)
            Spacer()

            if let percent {
                Text(String(format: "%+.1f%%", percent))
                    .monospacedDigit()
            } else {
                Text("-")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private func reload() {
        let db = DatabaseManager.shared
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        let last36 = cal.date(
            byAdding: .hour,
            value: -36,
            to: now
        ) ?? now

        let recentStart = cal.date(
            byAdding: .day,
            value: -7,
            to: today
        ) ?? today

        let previousStart = cal.date(
            byAdding: .day,
            value: -14,
            to: today
        ) ?? recentStart

        let previousEnd = recentStart

        let recentHRV = dailyWeightedAverage(
            metric: .hrv,
            from: recentStart,
            to: today,
            minimumDays: 3
        )
        let previousHRV = dailyWeightedAverage(
            metric: .hrv,
            from: previousStart,
            to: previousEnd,
            minimumDays: 3
        )

        let recentRHR = dailyWeightedAverage(
            metric: .restingHeartRate,
            from: recentStart,
            to: today,
            minimumDays: 3
        )
        let previousRHR = dailyWeightedAverage(
            metric: .restingHeartRate,
            from: previousStart,
            to: previousEnd,
            minimumDays: 3
        )

        let recentSleepSummary =
            db.sleepSummary(from: recentStart, to: today)
        let previousSleepSummary =
            db.sleepSummary(from: previousStart, to: previousEnd)

        let recentSleep: Double? = {
            guard let summary = recentSleepSummary,
                  summary.nights >= 3 else {
                return nil
            }
            return summary.hours / Double(summary.nights)
        }()

        let previousSleep: Double? = {
            guard let summary = previousSleepSummary,
                  summary.nights >= 3 else {
                return nil
            }
            return summary.hours / Double(summary.nights)
        }()

        let recentSteps: Double? =
            db.dailyMetricCoverageCount(
                for: .stepCount,
                from: recentStart,
                to: today
            ) >= 3
                ? db.averageDailyMetric(
                    for: .stepCount,
                    from: recentStart,
                    to: today
                )
                : nil

        let previousSteps: Double? =
            db.dailyMetricCoverageCount(
                for: .stepCount,
                from: previousStart,
                to: previousEnd
            ) >= 3
                ? db.averageDailyMetric(
                    for: .stepCount,
                    from: previousStart,
                    to: previousEnd
                )
                : nil

        let heart = db.latestSample(for: .heartRate)
        let resting = db.latestSample(for: .restingHeartRate)
        let hrv = db.latestSample(for: .hrv)
        let respiratory = db.latestSample(for: .respiratoryRate)

        snapshot = DashboardSnapshot(
            latestHeartRate: heart?.value,
            latestHeartRateAt: heart?.timestamp,
            restingHeartRate: resting?.value,
            restingHeartRateAt: resting?.timestamp,
            latestHRV: hrv?.value,
            latestHRVAt: hrv?.timestamp,
            respiratoryRate: respiratory?.value,
            respiratoryRateAt: respiratory?.timestamp,
            todaySteps: db.dailyMetricValue(
                for: .stepCount,
                dayStart: today
            ),
            lastSleepHours:
                db.sleepSummary(from: last36, to: now)?.hours,
            last7DaySymptoms:
                db.symptomCount(from: recentStart, to: now),
            hrvChangePercent:
                HealthAnalytics.percentChange(
                    new: recentHRV,
                    old: previousHRV
                ),
            restingHRChangePercent:
                HealthAnalytics.percentChange(
                    new: recentRHR,
                    old: previousRHR
                ),
            sleepChangePercent:
                HealthAnalytics.percentChange(
                    new: recentSleep,
                    old: previousSleep
                ),
            stepsChangePercent:
                HealthAnalytics.percentChange(
                    new: recentSteps,
                    old: previousSteps
                )
        )
    }

    private func dailyWeightedAverage(
        metric: HealthMetric,
        from: Date,
        to: Date,
        minimumDays: Int
    ) -> Double? {
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: to)
        var dailyValues: [Double] = []

        while cursor < end {
            guard let next = cal.date(
                byAdding: .day,
                value: 1,
                to: cursor
            ) else {
                break
            }

            if let value = DatabaseManager.shared.averageValue(
                for: metric,
                from: cursor,
                to: next
            ) {
                dailyValues.append(value)
            }

            cursor = next
        }

        guard dailyValues.count >= minimumDays else {
            return nil
        }

        return HealthAnalytics.average(dailyValues)
    }

    private func value(
        _ number: Double?,
        _ unit: String
    ) -> String {
        guard let number else { return "-" }
        return "\(String(format: "%.0f", number)) \(unit)"
    }

    private func integer(
        _ number: Double?
    ) -> String {
        guard let number else { return "-" }
        return String(format: "%.0f", number)
    }

    private func sleepText(
        _ hours: Double?
    ) -> String {
        guard let hours else { return "-" }
        return String(format: "%.1f h", hours)
    }

    private func relativeTime(
        _ date: Date
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(
            for: date,
            relativeTo: Date()
        )
    }
}
