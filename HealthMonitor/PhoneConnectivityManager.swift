import Foundation
import Combine
import WatchConnectivity

final class PhoneConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityManager()

    @Published private(set) var lastReceivedAt: Date?

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func pendingTransferCount() -> Int? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default.outstandingUserInfoTransfers.count
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            AppLogger.shared.error("WatchConnectivity activation: \(error.localizedDescription)")
        } else {
            AppLogger.shared.info("WatchConnectivity activation state=\(activationState.rawValue)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handle(userInfo)
    }

    private func handle(_ payload: [String: Any]) {
        guard
            let kind = payload["kind"] as? String,
            let eventID = payload["event_id"] as? String
        else {
            AppLogger.shared.warning("Watch payload rejected: missing kind/event_id")
            return
        }

        switch kind {
        case "symptom":
            let timestamp = Date(
                timeIntervalSince1970: payload["timestamp"] as? Double
                    ?? Date().timeIntervalSince1970
            )

            DatabaseManager.shared.addSymptom(
                eventID: eventID,
                timestamp: timestamp,
                symptom: payload["symptom"] as? String ?? "기타",
                posture: payload["posture"] as? String ?? "미상",
                severity: payload["severity"] as? Int ?? 5,
                heartRate: payload["heart_rate"] as? Double,
                note: payload["note"] as? String ?? "Apple Watch"
            ) { [weak self] success in
                self?.finishPersistence(
                    success: success,
                    kind: kind,
                    eventID: eventID
                )
            }

        case "orthostatic":
            let timestamp = Date(
                timeIntervalSince1970: payload["timestamp"] as? Double
                    ?? Date().timeIntervalSince1970
            )

            DatabaseManager.shared.addOrthostaticSession(
                eventID: eventID,
                timestamp: timestamp,
                baselineHeartRate: payload["baseline_hr"] as? Double,
                peakStandingHeartRate: payload["peak_standing_hr"] as? Double,
                finalStandingHeartRate: payload["final_standing_hr"] as? Double,
                peakDelta: payload["peak_delta"] as? Double,
                finalDelta: payload["final_delta"] as? Double,
                durationSeconds: payload["duration_seconds"] as? Int ?? 0,
                completed: payload["completed"] as? Bool ?? false,
                note: payload["note"] as? String ?? "Apple Watch"
            ) { [weak self] success in
                self?.finishPersistence(
                    success: success,
                    kind: kind,
                    eventID: eventID
                )
            }

        default:
            AppLogger.shared.warning("Unknown Watch payload kind=\(kind)")
        }
    }

    private func finishPersistence(
        success: Bool,
        kind: String,
        eventID: String
    ) {
        guard success else {
            AppLogger.shared.error(
                "Failed to persist Watch event kind=\(kind) event_id=\(eventID)"
            )
            return
        }

        lastReceivedAt = Date()
        AppLogger.shared.info(
            "Watch event persisted kind=\(kind) event_id=\(eventID)"
        )
        acknowledge(eventID: eventID)
    }

    private func acknowledge(eventID: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            AppLogger.shared.warning(
                "ACK deferred: WCSession inactive event_id=\(eventID)"
            )
            return
        }

        session.transferUserInfo([
            "kind": "ack",
            "event_id": eventID,
            "timestamp": Date().timeIntervalSince1970
        ])
        AppLogger.shared.info("Watch ACK queued event_id=\(eventID)")
    }
}
