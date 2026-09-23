import SwiftUI

@main
struct HealthMonitorWatchApp: App {
    @StateObject private var heartSession = LiveHeartSessionManager.shared
    @StateObject private var connectivity = WatchConnectivityManager.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(heartSession)
                .environmentObject(connectivity)
                .onAppear {
                    connectivity.activate()
                }
        }
    }
}
