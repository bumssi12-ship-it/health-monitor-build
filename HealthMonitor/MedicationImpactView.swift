import SwiftUI

struct MedicationImpactView: View {
    @State private var medications: [MedicationRecord] = []
    @State private var selectedID: Int64?
    @State private var comparison: MedicationComparison?
    @State private var showAddMedication = false

    private let minimumCoverageDays = 3

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        "약 변경 이벤트 전후의 건강 지표를 비교합니다. 시간적 변화만 보여주며 약의 효과나 부작용을 인과적으로 판정하지 않습니다."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Text(
                        "각 지표는 전/후 기간에 최소 \(minimumCoverageDays)일(수면은 \(minimumCoverageDays)회 밤) 기록이 있을 때만 값을 표시합니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("약 이벤트") {
                    Button {
                        showAddMedication = true
                    } label: {
                        Label(
                            "약 변경 이벤트 추가",
                            systemImage:
                                "plus.circle"
                        )
                    }

                    if medications.isEmpty {
                        Text(
                            "약 변경 이벤트를 추가하면 전후 비교를 시작할 수 있습니다."
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            "비교 기준",
                            selection:
                                $selectedID
                        ) {
                            ForEach(
                                medications
                            ) { item in
                                Text(label(item))
                                    .tag(
                                        Optional(
                                            item.id
                                        )
                                    )
                            }
                        }
                        .onChange(
                            of:
                                selectedID
                        ) {
                            _,
                            _ in

                            reloadComparison()
                        }
                    }
                }

                if let comparison {
                    Section(
                        "완료된 날짜 기준 비교"
                    ) {
                        HStack {
                            Text(
                                "비교 기간"
                            )
                            Spacer()
                            Text(
                                "전 \(comparison.beforeWindowDays)일 / 후 \(comparison.afterWindowDays)일"
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }

                        metricRow(
                            "안정시 심박",
                            before:
                                comparison.beforeRestingHR,
                            after:
                                comparison.afterRestingHR,
                            unit: "bpm",
                            beforeCoverage:
                                comparison.beforeRestingHRDays,
                            afterCoverage:
                                comparison.afterRestingHRDays,
                            coverageLabel:
                                "일"
                        )

                        metricRow(
                            "HRV",
                            before:
                                comparison.beforeHRV,
                            after:
                                comparison.afterHRV,
                            unit: "ms",
                            beforeCoverage:
                                comparison.beforeHRVDays,
                            afterCoverage:
                                comparison.afterHRVDays,
                            coverageLabel:
                                "일"
                        )

                        metricRow(
                            "수면/기록일",
                            before:
                                comparison.beforeSleepHoursPerDay,
                            after:
                                comparison.afterSleepHoursPerDay,
                            unit: "h",
                            beforeCoverage:
                                comparison.beforeSleepNights,
                            afterCoverage:
                                comparison.afterSleepNights,
                            coverageLabel:
                                "밤"
                        )

                        metricRow(
                            "걸음/일",
                            before:
                                comparison.beforeStepsPerDay,
                            after:
                                comparison.afterStepsPerDay,
                            unit: "",
                            beforeCoverage:
                                comparison.beforeStepDays,
                            afterCoverage:
                                comparison.afterStepDays,
                            coverageLabel:
                                "일"
                        )

                        if comparison.afterWindowDays == 0 {
                            Text(
                                "약 변경 다음 날부터 완료된 날짜가 생기면 '후' 비교가 시작됩니다."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Section(
                        "기준 이벤트"
                    ) {
                        Text(
                            label(
                                comparison
                                    .medication
                            )
                        )

                        if !comparison
                            .medication
                            .note
                            .isEmpty {
                            Text(
                                comparison
                                    .medication
                                    .note
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("약 변경 전후")
            .sheet(
                isPresented:
                    $showAddMedication
            ) {
                AddMedicationSheet {
                    reloadMedications()
                }
            }
            .onAppear {
                reloadMedications()
            }
        }
    }

    private func reloadMedications() {
        medications =
            DatabaseManager
                .shared
                .recentMedications(
                    limit: 100
                )

        if selectedID == nil
            || !medications
                .contains(
                    where: {
                        $0.id
                            == selectedID
                    }
                ) {
            selectedID =
                medications
                    .first?
                    .id
        }

        reloadComparison()
    }

    private func reloadComparison() {
        guard
            let selectedID,
            let medication =
                medications
                    .first(
                        where: {
                            $0.id
                                == selectedID
                        }
                    )
        else {
            comparison = nil
            return
        }

        let db =
            DatabaseManager.shared

        let cal =
            Calendar.current

        let eventDay =
            cal.startOfDay(
                for:
                    medication
                        .timestamp
            )

        let today =
            cal.startOfDay(
                for: Date()
            )

        let beforeStart =
            cal.date(
                byAdding: .day,
                value: -7,
                to: eventDay
            )
            ?? eventDay

        let beforeEnd =
            eventDay

        let afterStart =
            cal.date(
                byAdding: .day,
                value: 1,
                to: eventDay
            )
            ?? eventDay

        let afterTargetEnd =
            cal.date(
                byAdding: .day,
                value: 8,
                to: eventDay
            )
            ?? eventDay

        let afterEnd =
            min(
                today,
                afterTargetEnd
            )

        let beforeWindowDays =
            max(
                0,
                cal.dateComponents(
                    [.day],
                    from: beforeStart,
                    to: beforeEnd
                ).day
                ?? 0
            )

        let afterWindowDays =
            max(
                0,
                cal.dateComponents(
                    [.day],
                    from: afterStart,
                    to: afterEnd
                ).day
                ?? 0
            )

        let beforeRHRDays =
            db.recordedDayCount(
                for:
                    .restingHeartRate,
                from:
                    beforeStart,
                to:
                    beforeEnd
            )

        let afterRHRDays =
            db.recordedDayCount(
                for:
                    .restingHeartRate,
                from:
                    afterStart,
                to:
                    afterEnd
            )

        let beforeHRVDays =
            db.recordedDayCount(
                for:
                    .hrv,
                from:
                    beforeStart,
                to:
                    beforeEnd
            )

        let afterHRVDays =
            db.recordedDayCount(
                for:
                    .hrv,
                from:
                    afterStart,
                to:
                    afterEnd
            )

        let beforeSleepSummary =
            db.sleepSummary(
                from:
                    beforeStart,
                to:
                    beforeEnd
            )

        let afterSleepSummary =
            afterWindowDays > 0
            ? db.sleepSummary(
                from:
                    afterStart,
                to:
                    afterEnd
            )
            : nil

        let beforeSleepNights =
            beforeSleepSummary?
                .nights
            ?? 0

        let afterSleepNights =
            afterSleepSummary?
                .nights
            ?? 0

        let beforeStepDays =
            db.dailyMetricCoverageCount(
                for:
                    .stepCount,
                from:
                    beforeStart,
                to:
                    beforeEnd
            )

        let afterStepDays =
            afterWindowDays > 0
            ? db.dailyMetricCoverageCount(
                for:
                    .stepCount,
                from:
                    afterStart,
                to:
                    afterEnd
            )
            : 0

        comparison =
            MedicationComparison(
                medication:
                    medication,

                beforeRestingHR:
                    beforeRHRDays
                        >= minimumCoverageDays
                    ? dailyWeightedAverage(
                        .restingHeartRate,
                        from:
                            beforeStart,
                        to:
                            beforeEnd
                    )
                    : nil,

                afterRestingHR:
                    afterRHRDays
                        >= minimumCoverageDays
                    ? dailyWeightedAverage(
                        .restingHeartRate,
                        from:
                            afterStart,
                        to:
                            afterEnd
                    )
                    : nil,

                beforeRestingHRDays:
                    beforeRHRDays,
                afterRestingHRDays:
                    afterRHRDays,

                beforeHRV:
                    beforeHRVDays
                        >= minimumCoverageDays
                    ? dailyWeightedAverage(
                        .hrv,
                        from:
                            beforeStart,
                        to:
                            beforeEnd
                    )
                    : nil,

                afterHRV:
                    afterHRVDays
                        >= minimumCoverageDays
                    ? dailyWeightedAverage(
                        .hrv,
                        from:
                            afterStart,
                        to:
                            afterEnd
                    )
                    : nil,

                beforeHRVDays:
                    beforeHRVDays,
                afterHRVDays:
                    afterHRVDays,

                beforeSleepHoursPerDay:
                    beforeSleepNights
                        >= minimumCoverageDays
                    ? beforeSleepSummary
                        .map {
                            $0.hours
                                / Double(
                                    $0.nights
                                )
                        }
                    : nil,

                afterSleepHoursPerDay:
                    afterSleepNights
                        >= minimumCoverageDays
                    ? afterSleepSummary
                        .map {
                            $0.hours
                                / Double(
                                    $0.nights
                                )
                        }
                    : nil,

                beforeSleepNights:
                    beforeSleepNights,
                afterSleepNights:
                    afterSleepNights,

                beforeStepsPerDay:
                    beforeStepDays
                        >= minimumCoverageDays
                    ? db.averageDailyMetric(
                        for:
                            .stepCount,
                        from:
                            beforeStart,
                        to:
                            beforeEnd
                    )
                    : nil,

                afterStepsPerDay:
                    afterStepDays
                        >= minimumCoverageDays
                    ? db.averageDailyMetric(
                        for:
                            .stepCount,
                        from:
                            afterStart,
                        to:
                            afterEnd
                    )
                    : nil,

                beforeStepDays:
                    beforeStepDays,
                afterStepDays:
                    afterStepDays,

                beforeWindowDays:
                    beforeWindowDays,
                afterWindowDays:
                    afterWindowDays
            )
    }

    private func dailyWeightedAverage(
        _ metric: HealthMetric,
        from: Date,
        to: Date
    ) -> Double? {
        let cal =
            Calendar.current

        var cursor =
            cal.startOfDay(
                for: from
            )

        let end =
            cal.startOfDay(
                for: to
            )

        var values:
            [Double] = []

        while cursor < end {
            guard let next =
                cal.date(
                    byAdding: .day,
                    value: 1,
                    to: cursor
                )
            else {
                break
            }

            if let value =
                DatabaseManager
                    .shared
                    .averageValue(
                        for:
                            metric,
                        from:
                            cursor,
                        to:
                            next
                    ) {
                values.append(
                    value
                )
            }

            cursor = next
        }

        return
            HealthAnalytics
                .average(
                    values
                )
    }

    private func label(
        _ medication:
            MedicationRecord
    ) -> String {
        let dose =
            medication
                .dose
                .map {
                    String(
                        format:
                            "%.0f",
                        $0
                    )
                    + medication.unit
                }
            ?? ""

        let date =
            medication
                .timestamp
                .formatted(
                    date:
                        .abbreviated,
                    time:
                        .omitted
                )

        return
            "\(date) · \(medication.name) \(dose)"
    }

    private func metricRow(
        _ title: String,
        before: Double?,
        after: Double?,
        unit: String,
        beforeCoverage: Int,
        afterCoverage: Int,
        coverageLabel: String
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 4
        ) {
            HStack {
                Text(title)
                Spacer()

                Text(
                    format(
                        before,
                        unit: unit
                    )
                )
                .foregroundStyle(
                    .secondary
                )

                Image(
                    systemName:
                        "arrow.right"
                )
                .foregroundStyle(
                    .secondary
                )

                Text(
                    format(
                        after,
                        unit: unit
                    )
                )
                .bold()
            }

            Text(
                "기록 커버리지 · 전 \(beforeCoverage)\(coverageLabel) / 후 \(afterCoverage)\(coverageLabel)"
            )
            .font(.caption2)
            .foregroundStyle(
                .secondary
            )
        }
        .font(.subheadline)
    }

    private func format(
        _ value: Double?,
        unit: String
    ) -> String {
        guard let value else {
            return "-"
        }

        let number =
            unit.isEmpty
            ? String(
                format:
                    "%.0f",
                value
            )
            : String(
                format:
                    "%.1f",
                value
            )

        return
            unit.isEmpty
            ? number
            : "\(number) \(unit)"
    }
}

private struct AddMedicationSheet:
    View {

    @Environment(\.dismiss)
    private var dismiss

    @State private var date =
        Date()
    @State private var name =
        ""
    @State private var doseText =
        ""
    @State private var unit =
        "mg"
    @State private var note =
        ""
    @State private var saveError:
        String?

    let onSaved: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "날짜",
                    selection: $date,
                    in: ...Date()
                )

                TextField(
                    "약 이름",
                    text: $name
                )

                TextField(
                    "용량",
                    text: $doseText
                )
                .keyboardType(
                    .decimalPad
                )

                TextField(
                    "단위",
                    text: $unit
                )

                TextField(
                    "메모 (예: 증량)",
                    text: $note
                )

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(
                "약 이벤트 추가"
            )
            .toolbar {
                ToolbarItem(
                    placement:
                        .cancellationAction
                ) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement:
                        .confirmationAction
                ) {
                    Button("저장") {
                        save()
                    }
                    .disabled(
                        name
                            .trimmingCharacters(
                                in:
                                    .whitespacesAndNewlines
                            )
                            .isEmpty
                    )
                }
            }
        }
    }

    private func save() {
        let parsedDose =
            Double(
                doseText
                    .replacingOccurrences(
                        of: ",",
                        with: "."
                    )
            )

        DatabaseManager
            .shared
            .addMedication(
                date: date,
                name:
                    name
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        ),
                dose:
                    parsedDose,
                unit:
                    unit
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        ),
                note:
                    note
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
            ) {
                success in

                if success {
                    onSaved()
                    dismiss()
                } else {
                    saveError =
                        "저장하지 못했습니다. 다시 시도하세요."
                }
            }
    }
}
