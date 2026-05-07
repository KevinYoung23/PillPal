import SwiftUI
import UserNotifications

final class PillPalAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var appStore: AppStore?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        NotificationService.shared.registerCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let appStore {
            Task {
                await NotificationService.shared.handleAction(response: response, appStore: appStore)
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }
}

@main
struct PillPalApp: App {
    @UIApplicationDelegateAdaptor(PillPalAppDelegate.self) private var appDelegate
    @StateObject private var appStore = AppStore()

    var body: some Scene {
        WindowGroup {
            MainDockView()
                .environmentObject(appStore)
                .onAppear {
                    appDelegate.appStore = appStore
                }
        }
    }
}
