import Foundation
import Combine
import LocalAuthentication

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published private(set) var isUnlocked = false
    @Published private(set) var lastError: String?

    private init() {}

    func lock() {
        isUnlocked = false
        lastError = nil
    }

    func unlock(reason: String = "Health Monitor의 개인 건강 데이터를 확인합니다.") async {
        let context = LAContext()
        context.localizedCancelTitle = "취소"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            lastError = authError?.localizedDescription ?? "기기 인증을 사용할 수 없습니다."
            isUnlocked = false
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            isUnlocked = success
            lastError = success ? nil : "인증하지 못했습니다."
        } catch {
            isUnlocked = false
            lastError = error.localizedDescription
        }
    }
}
