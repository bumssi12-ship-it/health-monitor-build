import SwiftUI

@main
struct HealthMonitorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(HealthKitManager.shared)
        }
    }
}
