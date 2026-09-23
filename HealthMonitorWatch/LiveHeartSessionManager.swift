import Foundation
import Combine
import HealthKit
import WatchKit

enum OrthostaticPhase: String {
    case idle = "대기"
    case supine = "누워서 측정"
    case standing = "서서 측정"
    case finished = "완료"
    case stopped = "중단"
    case failed = "오류"
}

struct TimedHeartSample {
    let date: Date
    let bpm: Double
}

struct OrthostaticResult {
    let timestamp: Date
    let baselineHeartRate: Double?
    let peakStandingHeartRate: Double?
    let finalStandingHeartRate: Double?
    let peakDelta: Double?
    let finalDelta: Double?
    let durationSeconds: Int
    let completed: Bool
    let note: String
}

final class LiveHeartSessionManager: NSObject, ObservableObject {
    static let shared = LiveHeartSessionManager()

    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var phase: OrthostaticPhase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var lastResult: OrthostaticResult?
    @Published private(set) var errorMessage: String?
    @Published private(set) var authorizationRequestCompleted = false

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var timer: Timer?
    private var startDate: Date?
    private var standStartDate: Date?
    private var samples: [TimedHeartSample] = []
    private var pendingFinalPhase: OrthostaticPhase?

    private let supineDuration = 60
    private let standingDuration = 180

    private override init() {
        super.init()
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "HealthKit을 사용할 수 없습니다."
            completion(false)
            return
        }

        guard let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            errorMessage = "심박수 타입을 생성할 수 없습니다."
            completion(false)
            return
        }

        let read: Set<HKObjectType> = [heartRate]
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]

        healthStore.requestAuthorization(toShare: share, read: read) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.authorizationRequestCompleted = success
                self?.errorMessage = error?.localizedDescription
                completion(success)
            }
        }
    }

    func fetchLatestHeartRateEnsuringAuthorization(
        completion:
            @escaping (HeartRateReading?) -> Void
    ) {
        if authorizationRequestCompleted {
            fetchLatestHeartRateReading(
                completion: completion
            )
            return
        }

        requestAuthorization {
            [weak self]
            completed in

            guard
                completed,
                let self
            else {
                completion(nil)
                return
            }

            self.fetchLatestHeartRateReading(
                completion: completion
            )
        }
    }

    func fetchLatestHeartRateReading(
        completion:
            @escaping (HeartRateReading?) -> Void
    ) {
        guard let type =
            HKObjectType.quantityType(
                forIdentifier: .heartRate
            )
        else {
            completion(nil)
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
                sortDescriptors: [sort]
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

        healthStore.execute(query)
    }

    func startOrthostaticCheck() {
        guard phase == .idle || phase == .finished || phase == .stopped || phase == .failed else {
            return
        }

        requestAuthorization { [weak self] success in
            guard success else { return }
            self?.beginWorkoutSession()
        }
    }

    func stopEarly(reason: String = "사용자 중단") {
        guard startDate != nil else { return }
        complete(completed: false, note: reason)
    }

    private func beginWorkoutSession() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .mindAndBody
        configuration.locationType = .unknown

        do {
            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder

            samples.removeAll()
            currentHeartRate = nil
            lastResult = nil
            errorMessage = nil
            pendingFinalPhase = nil

            let now = Date()
            startDate = now
            standStartDate = nil
            phase = .supine
            remainingSeconds = supineDuration

            session.startActivity(with: now)
            builder.beginCollection(withStart: now) { [weak self] success, error in
                DispatchQueue.main.async {
                    guard let self else { return }

                    guard success, error == nil else {
                        self.failSession(
                            error?.localizedDescription ?? "측정을 시작할 수 없습니다."
                        )
                        return
                    }

                    self.startTimer()
                }
            }
        } catch {
            failSession(error.localizedDescription)
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let startDate else { return }
        let elapsed = max(0, Int(Date().timeIntervalSince(startDate)))

        if phase == .supine {
            remainingSeconds = max(0, supineDuration - elapsed)

            if elapsed >= supineDuration {
                phase = .standing
                standStartDate = Date()
                remainingSeconds = standingDuration
                WKInterfaceDevice.current().play(.notification)
            }
            return
        }

        if phase == .standing, let standStartDate {
            let standingElapsed = max(0, Int(Date().timeIntervalSince(standStartDate)))
            remainingSeconds = max(0, standingDuration - standingElapsed)

            if standingElapsed >= standingDuration {
                complete(completed: true, note: "1분 누움 + 3분 기립 완료")
            }
        }
    }

    private func complete(completed: Bool, note: String) {
        timer?.invalidate()
        timer = nil

        guard let startDate else { return }

        let now = Date()
        let duration = max(0, Int(now.timeIntervalSince(startDate)))
        let baselineWindowStart = startDate.addingTimeInterval(30)
        let baselineWindowEnd = startDate.addingTimeInterval(Double(supineDuration))

        let baselineSamples = samples
            .filter { $0.date >= baselineWindowStart && $0.date <= baselineWindowEnd }
            .map(\.bpm)

        let standingStart = standStartDate ?? startDate.addingTimeInterval(Double(supineDuration))
        let standingSamples = samples
            .filter { $0.date >= standingStart }
            .map(\.bpm)

        let finalWindowStart = now.addingTimeInterval(-30)
        let finalStandingSamples = samples
            .filter { $0.date >= maxDate(finalWindowStart, standingStart) && $0.date <= now }
            .map(\.bpm)

        let analysis = HealthAnalytics.orthostaticAnalysis(
            baselineSamples: baselineSamples,
            standingSamples: standingSamples,
            finalStandingSamples: finalStandingSamples
        )

        let result = OrthostaticResult(
            timestamp: startDate,
            baselineHeartRate: analysis.baselineHeartRate,
            peakStandingHeartRate: analysis.peakStandingHeartRate,
            finalStandingHeartRate: analysis.finalStandingHeartRate,
            peakDelta: analysis.peakDelta,
            finalDelta: analysis.finalDelta,
            durationSeconds: duration,
            completed: completed,
            note: note
        )

        lastResult = result
        remainingSeconds = 0
        pendingFinalPhase = completed ? .finished : .stopped

        let queued =
            WatchConnectivityManager
                .shared
                .sendOrthostatic(
                    result
                )

        if !queued {
            errorMessage =
                "기립 체크 결과를 전송 대기 저장소에 저장하지 못했습니다."
        }

        if let session = workoutSession {
            session.stopActivity(with: now)
        } else {
            finalizeStoppedSession()
        }
    }

    private func failSession(_ message: String) {
        timer?.invalidate()
        timer = nil
        errorMessage = message
        phase = .failed
        pendingFinalPhase = .failed

        if let session = workoutSession {
            session.stopActivity(with: Date())
        } else {
            workoutBuilder?.discardWorkout()
            resetSessionReferences()
        }
    }

    private func finalizeStoppedSession() {
        workoutBuilder?.discardWorkout()

        if let session = workoutSession, session.state != .ended {
            session.end()
        } else {
            resetSessionReferences()
        }
    }

    private func maxDate(_ lhs: Date, _ rhs: Date) -> Date {
        lhs > rhs ? lhs : rhs
    }

    private func appendHeartRate(_ value: Double, date: Date = Date()) {
        currentHeartRate = value
        samples.append(TimedHeartSample(date: date, bpm: value))
    }

    private func resetSessionReferences() {
        workoutSession = nil
        workoutBuilder = nil
        startDate = nil
        standStartDate = nil
        pendingFinalPhase = nil
    }
}

extension LiveHeartSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DispatchQueue.main.async {
            switch toState {
            case .stopped:
                if let final = self.pendingFinalPhase {
                    self.phase = final
                }
                self.finalizeStoppedSession()

            case .ended:
                self.resetSessionReferences()

            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = nil
            self.errorMessage = error.localizedDescription
            self.phase = .failed
            self.workoutBuilder?.discardWorkout()
            self.resetSessionReferences()
        }
    }
}

extension LiveHeartSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let heartType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        guard collectedTypes.contains(heartType) else { return }
        guard let statistics = workoutBuilder.statistics(for: heartType),
              let quantity = statistics.mostRecentQuantity() else {
            return
        }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let value = quantity.doubleValue(for: unit)

        DispatchQueue.main.async {
            self.appendHeartRate(value)
        }
    }
}
