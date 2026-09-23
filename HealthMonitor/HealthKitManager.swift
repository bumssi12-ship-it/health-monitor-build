import Foundation
import Combine
import HealthKit

final class HealthKitManager:
    NSObject,
    ObservableObject {

    static let shared = HealthKitManager()

    @Published private(set)
    var authorizationRequested = false

    @Published private(set)
    var lastSyncAt: Date?

    @Published private(set)
    var lastError: String?

    @Published private(set)
    var authorizationRequestStatusText =
        "확인 전"

    private enum SyncScope {
        case observer
        case full
    }

    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private let defaults =
        UserDefaults.standard

    private let stateQueue =
        DispatchQueue(
            label:
                "HealthMonitor.HealthKitSyncState"
        )

    private var inFlightMetrics =
        Set<HealthMetric>()

    private var rerunMetrics =
        Set<HealthMetric>()

    private var rerunFullMetrics =
        Set<HealthMetric>()

    private var pendingCompletions:
        [HealthMetric: [() -> Void]] = [:]

    // stateQueue-owned
    private var syncGeneration = 0
    private var resetInProgress = false
    private var resetRequested = false

    private let accessStateLock =
        NSLock()

    private var
        _dataAccessConfigured = false

    private var dataAccessConfigured: Bool {
        accessStateLock.lock()
        defer {
            accessStateLock.unlock()
        }
        return _dataAccessConfigured
    }

    private func setDataAccessConfigured(
        _ value: Bool
    ) {
        accessStateLock.lock()
        _dataAccessConfigured = value
        accessStateLock.unlock()
    }

    private override init() {
        super.init()

        lastSyncAt =
            defaults.object(
                forKey:
                    "health.lastSyncAt"
            ) as? Date
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore
            .isHealthDataAvailable()
    }

    private var anchoredSampleTypes:
        [(HKSampleType, HealthMetric)] {
        var result:
            [(HKSampleType, HealthMetric)] = []

        if let type =
            HKObjectType.quantityType(
                forIdentifier: .heartRate
            ) {
            result.append(
                (type, .heartRate)
            )
        }

        if let type =
            HKObjectType.quantityType(
                forIdentifier:
                    .restingHeartRate
            ) {
            result.append(
                (
                    type,
                    .restingHeartRate
                )
            )
        }

        if let type =
            HKObjectType.quantityType(
                forIdentifier:
                    .walkingHeartRateAverage
            ) {
            result.append(
                (
                    type,
                    .walkingHeartRate
                )
            )
        }

        if let type =
            HKObjectType.quantityType(
                forIdentifier:
                    .heartRateVariabilitySDNN
            ) {
            result.append(
                (type, .hrv)
            )
        }

        if let type =
            HKObjectType.quantityType(
                forIdentifier:
                    .respiratoryRate
            ) {
            result.append(
                (
                    type,
                    .respiratoryRate
                )
            )
        }

        if let type =
            HKObjectType.categoryType(
                forIdentifier:
                    .sleepAnalysis
            ) {
            result.append(
                (type, .sleep)
            )
        }

        return result
    }

    private var observedSampleTypes:
        [(HKSampleType, HealthMetric)] {
        var result =
            anchoredSampleTypes

        if let type =
            HKObjectType.quantityType(
                forIdentifier:
                    .stepCount
            ) {
            result.append(
                (type, .stepCount)
            )
        }

        return result
    }

    private var readTypes:
        Set<HKObjectType> {
        Set(
            observedSampleTypes.map {
                $0.0 as HKObjectType
            }
        )
    }

    func prepareForLaunch() {
        guard
            isHealthDataAvailable
        else {
            return
        }

        // Apple recommends creating observer queries during app launch so
        // background-delivery launches have handlers ready immediately.
        registerObserversIfNeeded()

        store
            .getRequestStatusForAuthorization(
                toShare: [],
                read: readTypes
            ) {
                [weak self]
                status,
                error in

                guard let self else {
                    return
                }

                if let error {
                    AppLogger.shared.error(
                        "Health launch authorization status: "
                        + error.localizedDescription
                    )

                    DispatchQueue.main.async {
                        self.lastError =
                            error.localizedDescription
                        self
                            .authorizationRequestStatusText =
                            "확인 실패"
                    }
                    return
                }

                DispatchQueue.main.async {
                    self
                        .authorizationRequestStatusText =
                        self.statusText(
                            status
                        )
                }

                if status
                    == .unnecessary {
                    self
                        .setDataAccessConfigured(
                            true
                        )

                    _ = self.syncOrigin()

                    self
                        .registerObserversIfNeeded()

                    self
                        .enableBackgroundDelivery()

                    self
                        .syncAllIncremental()
                }
            }
    }

    func requestAuthorization(
        completion:
            @escaping (Bool) -> Void
    ) {
        guard
            isHealthDataAvailable
        else {
            DispatchQueue.main.async {
                self.lastError =
                    "이 기기에서는 HealthKit을 사용할 수 없습니다."
                completion(false)
            }
            return
        }

        store.requestAuthorization(
            toShare: [],
            read: readTypes
        ) {
            [weak self]
            success,
            error in

            guard let self else {
                return
            }

            DispatchQueue.main.async {
                self
                    .authorizationRequested =
                    true

                if let error {
                    self.lastError =
                        error.localizedDescription
                }
            }

            if success {
                self
                    .setDataAccessConfigured(
                        true
                    )

                _ = self.syncOrigin()

                self
                    .registerObserversIfNeeded()

                self
                    .enableBackgroundDelivery()

                self
                    .syncAllIncremental()

                AppLogger.shared.info(
                    "Health authorization request completed"
                )
            } else if let error {
                AppLogger.shared.error(
                    "Health authorization: "
                    + error.localizedDescription
                )
            }

            self
                .refreshAuthorizationRequestStatus()

            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    private func registerObserversIfNeeded() {
        guard
            isHealthDataAvailable
        else {
            return
        }

        stateQueue.sync {
            guard
                self.observerQueries.isEmpty,
                !self.resetInProgress
            else {
                return
            }

            for (
                type,
                metric
            ) in self.observedSampleTypes {
                let query =
                    HKObserverQuery(
                        sampleType: type,
                        predicate: nil
                    ) {
                        [weak self]
                        _,
                        completionHandler,
                        error in

                        guard
                            let self
                        else {
                            completionHandler()
                            return
                        }

                        if let error {
                            DispatchQueue
                                .main
                                .async {
                                    self.lastError =
                                        error
                                            .localizedDescription
                                }

                            AppLogger
                                .shared
                                .error(
                                    "Observer "
                                    + metric.rawValue
                                    + ": "
                                    + error
                                        .localizedDescription
                                )

                            completionHandler()
                            return
                        }

                        guard self.dataAccessConfigured else {
                            completionHandler()
                            return
                        }

                        self.syncMetric(
                            type: type,
                            metric: metric,
                            scope: .observer,
                            completion:
                                completionHandler
                        )
                    }

                self
                    .observerQueries
                    .append(query)

                self.store.execute(
                    query
                )
            }
        }
    }

    private func enableBackgroundDelivery() {
        guard
            dataAccessConfigured
        else {
            return
        }

        for (
            type,
            metric
        ) in observedSampleTypes {
            store
                .enableBackgroundDelivery(
                    for: type,
                    frequency: .hourly
                ) {
                    [weak self]
                    success,
                    error in

                    if success {
                        AppLogger
                            .shared
                            .info(
                                "Background delivery enabled hourly: "
                                + metric.rawValue
                            )
                    } else if let error {
                        DispatchQueue
                            .main
                            .async {
                                self?.lastError =
                                    "Background delivery: "
                                    + error
                                        .localizedDescription
                            }

                        AppLogger
                            .shared
                            .error(
                                "Background delivery "
                                + metric.rawValue
                                + ": "
                                + error
                                    .localizedDescription
                            )
                    }
                }
        }
    }

    func syncAllIncremental() {
        guard
            dataAccessConfigured
        else {
            AppLogger.shared.info(
                "Health sync skipped until authorization flow is configured"
            )
            return
        }

        let resetting =
            stateQueue.sync {
                resetInProgress
            }

        guard !resetting else {
            AppLogger.shared.info(
                "Health sync skipped during cache rebuild"
            )
            return
        }

        for (
            type,
            metric
        ) in observedSampleTypes {
            syncMetric(
                type: type,
                metric: metric,
                scope: .full,
                completion: {}
            )
        }
    }

    func resetAnchorsAndResync() {
        let queriesToStop:
            [HKObserverQuery] =
            stateQueue.sync {
                if resetInProgress {
                    return []
                }

                resetInProgress = true
                resetRequested = true
                syncGeneration += 1

                rerunMetrics.removeAll()
                rerunFullMetrics.removeAll()

                let queries =
                    observerQueries

                observerQueries
                    .removeAll()

                return queries
            }

        for query in queriesToStop {
            store.stop(query)
        }

        stateQueue.async {
            self
                .performResetIfReady()
        }
    }

    private func performResetIfReady() {
        dispatchPrecondition(
            condition:
                .onQueue(stateQueue)
        )

        guard
            resetInProgress,
            resetRequested,
            inFlightMetrics.isEmpty
        else {
            return
        }

        resetRequested = false

        DatabaseManager
            .shared
            .resetHealthCache {
                [weak self]
                success in

                guard let self else {
                    return
                }

                if success {
                    for (
                        _,
                        metric
                    ) in self
                        .anchoredSampleTypes {
                        self.defaults
                            .removeObject(
                                forKey:
                                    self.anchorKey(
                                        metric
                                    )
                            )
                    }

                    // Keep the original sync origin.
                    // This prevents a rebuild after long-term use
                    // from silently truncating older locally cached history.
                    _ = self.syncOrigin()

                    self.defaults
                        .removeObject(
                            forKey:
                                "health.lastSyncAt"
                        )

                    DispatchQueue.main.async {
                        self.lastSyncAt =
                            nil
                    }

                    AppLogger
                        .shared
                        .warning(
                            "Health local cache and anchors rebuilt from preserved sync origin"
                        )
                }

                self.stateQueue.async {
                    self
                        .resetInProgress =
                        false

                    DispatchQueue
                        .main
                        .async {
                            if !success {
                                self.lastError =
                                    "로컬 Health 캐시 초기화에 실패했습니다."
                            }

                            self
                                .registerObserversIfNeeded()

                            self
                                .enableBackgroundDelivery()

                            if success {
                                self
                                    .syncAllIncremental()
                            }
                        }
                }
            }
    }

    func storedAnchorCount() -> Int {
        anchoredSampleTypes
            .reduce(into: 0) {
                count,
                pair in

                if defaults.data(
                    forKey:
                        anchorKey(
                            pair.1
                        )
                ) != nil {
                    count += 1
                }
            }
    }

    func refreshAuthorizationRequestStatus() {
        guard
            isHealthDataAvailable
        else {
            DispatchQueue.main.async {
                self
                    .authorizationRequestStatusText =
                    "HealthKit 사용 불가"
            }
            return
        }

        store
            .getRequestStatusForAuthorization(
                toShare: [],
                read: readTypes
            ) {
                [weak self]
                status,
                error in

                DispatchQueue.main.async {
                    if let error {
                        self?
                            .authorizationRequestStatusText =
                            "확인 실패"
                        self?.lastError =
                            error
                                .localizedDescription
                        return
                    }

                    self?
                        .authorizationRequestStatusText =
                        self?
                            .statusText(
                                status
                            )
                        ?? "알 수 없음"
                }
            }
    }

    private func statusText(
        _ status:
            HKAuthorizationRequestStatus
    ) -> String {
        switch status {
        case .shouldRequest:
            return "권한 요청 화면 필요"

        case .unnecessary:
            return "추가 권한 요청 불필요"

        case .unknown:
            return "알 수 없음"

        @unknown default:
            return "알 수 없음"
        }
    }

    func fetchLatestHeartRateReading(
        completion:
            @escaping (HeartRateReading?) -> Void
    ) {
        guard
            dataAccessConfigured
        else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        guard let type =
            HKObjectType.quantityType(
                forIdentifier:
                    .heartRate
            )
        else {
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        let sort =
            NSSortDescriptor(
                key:
                    HKSampleSortIdentifierStartDate,
                ascending: false
            )

        let query =
            HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [
                    sort
                ]
            ) {
                _,
                samples,
                _ in

                guard let sample =
                    samples?.first
                    as? HKQuantitySample
                else {
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }

                let unit =
                    HKUnit.count()
                        .unitDivided(
                            by: .minute()
                        )

                let reading =
                    HeartRateReading(
                        value:
                            sample.quantity
                                .doubleValue(
                                    for: unit
                                ),
                        timestamp:
                            sample.endDate
                    )

                DispatchQueue.main.async {
                    completion(reading)
                }
            }

        store.execute(query)
    }

    func fetchLatestHeartRate(
        completion:
            @escaping (Double?) -> Void
    ) {
        fetchLatestHeartRateReading {
            completion($0?.value)
        }
    }

    private func syncMetric(
        type: HKSampleType,
        metric: HealthMetric,
        scope: SyncScope,
        completion:
            @escaping () -> Void
    ) {
        stateQueue.async {
            if self.resetInProgress {
                DispatchQueue.main.async {
                    completion()
                }
                return
            }

            self
                .pendingCompletions[
                    metric,
                    default: []
                ]
                .append(
                    completion
                )

            if self
                .inFlightMetrics
                .contains(metric) {
                self
                    .rerunMetrics
                    .insert(metric)

                if scope == .full {
                    self
                        .rerunFullMetrics
                        .insert(metric)
                }

                return
            }

            self
                .inFlightMetrics
                .insert(metric)

            self
                .startMetricSync(
                    type: type,
                    metric: metric,
                    scope: scope,
                    generation:
                        self
                            .syncGeneration
                )
        }
    }

    private func startMetricSync(
        type: HKSampleType,
        metric: HealthMetric,
        scope: SyncScope,
        generation: Int
    ) {
        performMetricSync(
            type: type,
            metric: metric,
            scope: scope,
            generation: generation
        ) {
            self.stateQueue.async {
                if self.resetInProgress {
                    self
                        .inFlightMetrics
                        .remove(metric)

                    self
                        .rerunMetrics
                        .remove(metric)

                    self
                        .rerunFullMetrics
                        .remove(metric)

                    let completions =
                        self
                            .pendingCompletions
                            .removeValue(
                                forKey:
                                    metric
                            )
                        ?? []

                    DispatchQueue
                        .main
                        .async {
                            completions
                                .forEach {
                                    $0()
                                }
                        }

                    self
                        .performResetIfReady()

                    return
                }

                if self
                    .rerunMetrics
                    .remove(metric)
                    != nil {
                    let nextScope:
                        SyncScope =
                        self
                            .rerunFullMetrics
                            .remove(metric)
                        != nil
                        ? .full
                        : .observer

                    self
                        .startMetricSync(
                            type: type,
                            metric: metric,
                            scope:
                                nextScope,
                            generation:
                                self
                                    .syncGeneration
                        )

                    return
                }

                self
                    .inFlightMetrics
                    .remove(metric)

                let completions =
                    self
                        .pendingCompletions
                        .removeValue(
                            forKey:
                                metric
                        )
                    ?? []

                DispatchQueue.main.async {
                    completions
                        .forEach {
                            $0()
                        }
                }
            }
        }
    }

    private func performMetricSync(
        type: HKSampleType,
        metric: HealthMetric,
        scope: SyncScope,
        generation: Int,
        completion:
            @escaping () -> Void
    ) {
        if metric
            == .stepCount {
            // A step edit/deletion may affect any date in the
            // locally cached 30-day window. Refresh the whole
            // window for correctness; background wakes are hourly.
            refreshDailySteps(
                daysBack: 30,
                generation: generation,
                completion: completion
            )
        } else {
            performAnchoredSync(
                type: type,
                metric: metric,
                generation: generation,
                completion: completion
            )
        }
    }

    private func performAnchoredSync(
        type: HKSampleType,
        metric: HealthMetric,
        generation: Int,
        completion:
            @escaping () -> Void
    ) {
        let origin =
            syncOrigin()

        let predicate =
            HKQuery
                .predicateForSamples(
                    withStart: origin,
                    end: nil,
                    options:
                        .strictStartDate
                )

        let query =
            HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor:
                    loadAnchor(
                        for: metric
                    ),
                limit:
                    HKObjectQueryNoLimit
            ) {
                [weak self]
                _,
                samples,
                deletedObjects,
                newAnchor,
                error in

                guard let self else {
                    completion()
                    return
                }

                if let error {
                    AppLogger
                        .shared
                        .error(
                            "Anchored query "
                            + metric.rawValue
                            + ": "
                            + error
                                .localizedDescription
                        )

                    DispatchQueue
                        .main
                        .async {
                            self.lastError =
                                error
                                    .localizedDescription
                        }

                    completion()
                    return
                }

                guard
                    self
                        .generationIsCurrent(
                            generation
                        )
                else {
                    completion()
                    return
                }

                let records =
                    (samples ?? [])
                        .compactMap {
                            self
                                .makeRecord(
                                    sample: $0,
                                    metric:
                                        metric
                                )
                        }

                let deletedUUIDs =
                    (deletedObjects ?? [])
                        .map(
                            \.uuid
                        )

                DatabaseManager
                    .shared
                    .applyHealthKitChanges(
                        samples: records,
                        deletedUUIDs:
                            deletedUUIDs
                    ) {
                        success in

                        guard success else {
                            completion()
                            return
                        }

                        guard
                            self
                                .generationIsCurrent(
                                    generation
                                )
                        else {
                            completion()
                            return
                        }

                        if let newAnchor {
                            self
                                .saveAnchor(
                                    newAnchor,
                                    for:
                                        metric
                                )
                        }

                        AppLogger
                            .shared
                            .info(
                                "Health sync "
                                + metric.rawValue
                                + ": added="
                                + String(
                                    records
                                        .count
                                )
                                + ", deleted="
                                + String(
                                    deletedUUIDs
                                        .count
                                )
                            )

                        self
                            .markSyncComplete()

                        completion()
                    }
            }

        store.execute(query)
    }

    private func refreshDailySteps(
        daysBack: Int,
        generation: Int,
        completion:
            @escaping () -> Void
    ) {
        guard let stepType =
            HKObjectType.quantityType(
                forIdentifier:
                    .stepCount
            )
        else {
            completion()
            return
        }

        let calendar =
            Calendar.current

        let today =
            calendar.startOfDay(
                for: Date()
            )

        let start =
            calendar.date(
                byAdding: .day,
                value:
                    -max(
                        1,
                        daysBack
                    ),
                to: today
            )
            ?? today

        let end =
            calendar.date(
                byAdding: .day,
                value: 1,
                to: today
            )
            ?? Date()

        let predicate =
            HKQuery
                .predicateForSamples(
                    withStart: start,
                    end: end,
                    options:
                        .strictStartDate
                )

        let query =
            HKStatisticsCollectionQuery(
                quantityType:
                    stepType,
                quantitySamplePredicate:
                    predicate,
                options:
                    .cumulativeSum,
                anchorDate:
                    today,
                intervalComponents:
                    DateComponents(
                        day: 1
                    )
            )

        query.initialResultsHandler = {
            [weak self]
            _,
            collection,
            error in

            guard let self else {
                completion()
                return
            }

            if let error {
                AppLogger
                    .shared
                    .error(
                        "Step statistics query: "
                        + error
                            .localizedDescription
                    )

                DispatchQueue.main.async {
                    self.lastError =
                        error
                            .localizedDescription
                }

                completion()
                return
            }

            guard
                self
                    .generationIsCurrent(
                        generation
                    )
            else {
                completion()
                return
            }

            var records:
                [DailyMetricRecord] = []

            collection?
                .enumerateStatistics(
                    from: start,
                    to: end
                ) {
                    statistics,
                    _ in

                    guard let sum =
                        statistics
                            .sumQuantity()
                    else {
                        return
                    }

                    records.append(
                        DailyMetricRecord(
                            dayStart:
                                calendar
                                    .startOfDay(
                                        for:
                                            statistics
                                                .startDate
                                    ),
                            type:
                                .stepCount,
                            value:
                                sum
                                    .doubleValue(
                                        for:
                                            .count()
                                    ),
                            unit:
                                "count"
                        )
                    )
                }

            guard
                self
                    .generationIsCurrent(
                        generation
                    )
            else {
                completion()
                return
            }

            DatabaseManager
                .shared
                .replaceDailyMetrics(
                    for:
                        .stepCount,
                    from: start,
                    to: end,
                    records:
                        records
                ) {
                    success in

                    guard success else {
                        AppLogger
                            .shared
                            .error(
                                "Step daily metrics persistence failed"
                            )

                        completion()
                        return
                    }

                    guard
                        self
                            .generationIsCurrent(
                                generation
                            )
                    else {
                        completion()
                        return
                    }

                    AppLogger
                        .shared
                        .info(
                            "Step statistics refreshed: "
                            + String(
                                records.count
                            )
                            + " days"
                        )

                    self
                        .markSyncComplete()

                    completion()
                }
        }

        store.execute(query)
    }

    private func generationIsCurrent(
        _ generation: Int
    ) -> Bool {
        stateQueue.sync {
            generation
                == syncGeneration
                && !resetInProgress
        }
    }

    private func makeRecord(
        sample: HKSample,
        metric: HealthMetric
    ) -> HealthSampleRecord? {
        let source =
            sample
                .sourceRevision
                .source
                .name

        let uuid =
            sample
                .uuid
                .uuidString

        if let quantity =
            sample as? HKQuantitySample {
            let (
                value,
                unitText
            ) =
                convert(
                    quantity:
                        quantity,
                    metric:
                        metric
                )

            return HealthSampleRecord(
                uuid: uuid,
                type: metric,
                start:
                    quantity
                        .startDate,
                end:
                    quantity
                        .endDate,
                value: value,
                unit:
                    unitText,
                source:
                    source
            )
        }

        if let category =
            sample as? HKCategorySample,
           metric == .sleep {
            let asleepValues:
                Set<Int> = [
                    HKCategoryValueSleepAnalysis
                        .asleepUnspecified
                        .rawValue,
                    HKCategoryValueSleepAnalysis
                        .asleepCore
                        .rawValue,
                    HKCategoryValueSleepAnalysis
                        .asleepDeep
                        .rawValue,
                    HKCategoryValueSleepAnalysis
                        .asleepREM
                        .rawValue
                ]

            guard
                asleepValues
                    .contains(
                        category
                            .value
                    )
            else {
                return nil
            }

            return HealthSampleRecord(
                uuid: uuid,
                type: .sleep,
                start:
                    category
                        .startDate,
                end:
                    category
                        .endDate,
                value:
                    category
                        .endDate
                        .timeIntervalSince(
                            category
                                .startDate
                        )
                    / 3600.0,
                unit: "h",
                source:
                    source
            )
        }

        return nil
    }

    private func markSyncComplete() {
        let now = Date()

        defaults.set(
            now,
            forKey:
                "health.lastSyncAt"
        )

        DispatchQueue.main.async {
            self.lastSyncAt =
                now
        }
    }

    private var syncOriginKey: String {
        "health.syncOrigin.v2"
    }

    private func syncOrigin() -> Date {
        if let existing =
            defaults.object(
                forKey:
                    syncOriginKey
            ) as? Date {
            return existing
        }

        let calendar =
            Calendar.current

        let today =
            calendar
                .startOfDay(
                    for: Date()
                )

        let origin =
            calendar.date(
                byAdding: .day,
                value: -30,
                to: today
            )
            ?? today

        defaults.set(
            origin,
            forKey:
                syncOriginKey
        )

        return origin
    }

    private func anchorKey(
        _ metric: HealthMetric
    ) -> String {
        "health.anchor."
            + metric.rawValue
            + ".v2"
    }

    private func saveAnchor(
        _ anchor: HKQueryAnchor,
        for metric:
            HealthMetric
    ) {
        do {
            let data =
                try NSKeyedArchiver
                    .archivedData(
                        withRootObject:
                            anchor,
                        requiringSecureCoding:
                            true
                    )

            defaults.set(
                data,
                forKey:
                    anchorKey(
                        metric
                    )
            )
        } catch {
            AppLogger.shared.error(
                "Anchor save "
                + metric.rawValue
                + ": "
                + error
                    .localizedDescription
            )
        }
    }

    private func loadAnchor(
        for metric:
            HealthMetric
    ) -> HKQueryAnchor? {
        guard let data =
            defaults.data(
                forKey:
                    anchorKey(
                        metric
                    )
            )
        else {
            return nil
        }

        do {
            return try
                NSKeyedUnarchiver
                    .unarchivedObject(
                        ofClass:
                            HKQueryAnchor
                                .self,
                        from:
                            data
                    )
        } catch {
            defaults
                .removeObject(
                    forKey:
                        anchorKey(
                            metric
                        )
                )

            AppLogger
                .shared
                .warning(
                    "Corrupt anchor reset: "
                    + metric.rawValue
                )

            return nil
        }
    }

    private func convert(
        quantity:
            HKQuantitySample,
        metric:
            HealthMetric
    ) -> (Double, String) {
        switch metric {
        case .heartRate,
             .restingHeartRate,
             .walkingHeartRate:
            let unit =
                HKUnit.count()
                    .unitDivided(
                        by: .minute()
                    )

            return (
                quantity
                    .quantity
                    .doubleValue(
                        for: unit
                    ),
                "bpm"
            )

        case .hrv:
            let unit =
                HKUnit.secondUnit(
                    with: .milli
                )

            return (
                quantity
                    .quantity
                    .doubleValue(
                        for: unit
                    ),
                "ms"
            )

        case .respiratoryRate:
            let unit =
                HKUnit.count()
                    .unitDivided(
                        by: .minute()
                    )

            return (
                quantity
                    .quantity
                    .doubleValue(
                        for: unit
                    ),
                "breaths/min"
            )

        case .stepCount:
            return (
                quantity
                    .quantity
                    .doubleValue(
                        for: .count()
                    ),
                "count"
            )

        case .sleep:
            return (
                0,
                "h"
            )
        }
    }
}
