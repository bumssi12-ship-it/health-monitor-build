import Foundation
import Combine
import WatchConnectivity

final class WatchConnectivityManager:
    NSObject,
    ObservableObject,
    WCSessionDelegate {

    static let shared = WatchConnectivityManager()

    @Published private(set) var lastTransferAt: Date?
    @Published private(set) var pendingTransfers = 0
    @Published private(set) var lastError: String?

    private let pendingStore =
        PendingWatchEventStore.shared

    private var retryScheduled = false

    private override init() {
        super.init()
        pendingTransfers = pendingStore.count()
    }

    func activate() {
        guard WCSession.isSupported() else {
            lastError = "WatchConnectivity를 사용할 수 없습니다."
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
        refreshPending()
    }

    @discardableResult
    func sendSymptom(
        symptom: String,
        posture: String,
        severity: Int,
        heartRate: Double?
    ) -> Bool {
        let eventID = UUID().uuidString

        var payload: [String: Any] = [
            "event_id": eventID,
            "kind": "symptom",
            "timestamp": Date().timeIntervalSince1970,
            "symptom": symptom,
            "posture": posture,
            "severity": max(0, min(10, severity)),
            "note": "Apple Watch"
        ]

        if let heartRate {
            payload["heart_rate"] = heartRate
        }

        return queueDurably(payload)
    }

    @discardableResult
    func sendOrthostatic(
        _ result: OrthostaticResult
    ) -> Bool {
        let eventID = UUID().uuidString

        var payload: [String: Any] = [
            "event_id": eventID,
            "kind": "orthostatic",
            "timestamp":
                result.timestamp.timeIntervalSince1970,
            "duration_seconds": result.durationSeconds,
            "completed": result.completed,
            "note": result.note
        ]

        if let value = result.baselineHeartRate {
            payload["baseline_hr"] = value
        }
        if let value = result.peakStandingHeartRate {
            payload["peak_standing_hr"] = value
        }
        if let value = result.finalStandingHeartRate {
            payload["final_standing_hr"] = value
        }
        if let value = result.peakDelta {
            payload["peak_delta"] = value
        }
        if let value = result.finalDelta {
            payload["final_delta"] = value
        }

        return queueDurably(payload)
    }

    @discardableResult
    private func queueDurably(
        _ payload: [String: Any]
    ) -> Bool {
        let persisted =
            pendingStore.enqueue(
                payload
            )

        guard persisted else {
            DispatchQueue.main.async {
                self.lastError =
                    self.pendingStore
                        .storageError()
                    ?? "전송 대기 기록을 로컬에 저장하지 못했습니다."
            }

            refreshPending()
            return false
        }

        DispatchQueue.main.async {
            self.lastError = nil
        }

        refreshPending()
        transfer(payload)
        return true
    }


func retryPendingNow() {
    guard
        WCSession.default.activationState
            == .activated
    else {
        activate()
        return
    }

    lastError = nil
    resendPending()
}

private func scheduleRetry() {
    guard !retryScheduled else {
        return
    }

    retryScheduled = true

    DispatchQueue.main.asyncAfter(
        deadline: .now() + 15
    ) {
        self.retryScheduled = false

        guard
            WCSession.default.activationState
                == .activated,
            self.pendingStore.count() > 0
        else {
            return
        }

        self.resendPending()
    }
}

    private func transfer(
        _ payload: [String: Any]
    ) {
        guard
            WCSession.default.activationState == .activated
        else {
            activate()
            return
        }

        WCSession.default.transferUserInfo(payload)

        DispatchQueue.main.async {
            self.lastTransferAt = Date()
        }
    }

    private func resendPending() {
        guard
            WCSession.default.activationState == .activated
        else {
            return
        }

        let outstandingIDs = Set(
            WCSession.default
                .outstandingUserInfoTransfers
                .compactMap {
                    $0.userInfo["event_id"] as? String
                }
        )

        for payload in pendingStore.all() {
            guard let eventID =
                payload["event_id"] as? String else {
                continue
            }

            guard !outstandingIDs.contains(eventID) else {
                continue
            }

            WCSession.default.transferUserInfo(payload)
        }

        refreshPending()
    }

    private func refreshPending() {
        let count =
            pendingStore.count()
        let storageError =
            pendingStore.storageError()

        DispatchQueue.main.async {
            self.pendingTransfers =
                count

            if let storageError {
                self.lastError =
                    storageError
            }
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith
            activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            if let error {
                self.lastError =
                    error.localizedDescription
            }

            self.refreshPending()

            if activationState == .activated {
                self.resendPending()
            }
        }
    }

    func session(
        _ session: WCSession,
        didFinish
            userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        DispatchQueue.main.async {
            if let error {
                self.lastError =
                    "전송 실패: \(error.localizedDescription)"
                self.scheduleRetry()
            }
            self.refreshPending()
        }
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo
            userInfo: [String: Any] = [:]
    ) {
        guard
            userInfo["kind"] as? String == "ack",
            let eventID =
                userInfo["event_id"] as? String
        else {
            return
        }

        let removed =
            pendingStore.remove(eventID: eventID)

        DispatchQueue.main.async {
            if !removed {
                self.lastError =
                    "ACK 수신 후 로컬 대기열 갱신에 실패했습니다."
            }
            self.refreshPending()
        }
    }
}
