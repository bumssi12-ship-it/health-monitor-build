import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        DatabaseManager.shared.initializeDatabase()
        PhoneConnectivityManager.shared.activate()
        HealthKitManager.shared.prepareForLaunch()
        AppLogger.shared.info("Application launched")
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppLogger.shared.info("Application entered background")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        AppLogger.shared.info("Application entering foreground")
        HealthKitManager.shared.prepareForLaunch()
        HealthKitManager.shared.syncAllIncremental()
    }
}
