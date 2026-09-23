import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("privacy.appLockEnabled") private var appLockEnabled = false
    @StateObject private var lockManager = AppLockManager.shared

    var body: some View {
        ZStack {
            Group {
                if !appLockEnabled || lockManager.isUnlocked {
                    ContentView()
                } else {
                    LockedView()
                }
            }

            // Cover health data before iOS captures an inactive/background snapshot.
            if appLockEnabled && scenePhase != .active {
                PrivacyCoverView()
                    .zIndex(100)
            }
        }
        .onAppear {
            authenticateIfNeeded()
        }
        .onChange(of: appLockEnabled) { _, enabled in
            if enabled {
                lockManager.lock()
                Task {
                    await lockManager.unlock()
                }
            } else {
                // Keep the internal state locked so turning protection on again
                // always requires a fresh authentication.
                lockManager.lock()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard appLockEnabled else { return }

            switch newPhase {
            case .inactive, .background:
                lockManager.lock()

            case .active:
                authenticateIfNeeded()

            @unknown default:
                lockManager.lock()
            }
        }
    }

    private func authenticateIfNeeded() {
        guard appLockEnabled, !lockManager.isUnlocked else { return }
        Task {
            await lockManager.unlock()
        }
    }
}

private struct LockedView: View {
    @StateObject private var lockManager = AppLockManager.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))

            Text("Health Monitor 잠금")
                .font(.title2.bold())

            Text("개인 건강 기록을 보려면 Face ID, Touch ID 또는 기기 암호로 인증하세요.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("잠금 해제") {
                Task {
                    await lockManager.unlock()
                }
            }
            .buttonStyle(.borderedProminent)

            if let error = lockManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

private struct PrivacyCoverView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.largeTitle)
            Text("Health Monitor")
                .font(.headline)
            Text("개인 건강 기록 보호 중")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
    }
}
