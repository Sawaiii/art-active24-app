import SwiftUI
import UIKit
import UserNotifications

@main
struct ArtActiveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var env = AppEnvironment.live()

    init() {
        Appearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(env.router)
                .environment(env.auth)
                .environment(env.cart)
                .environment(env.favorites)
                .environment(env.recent)
                .environment(env.orders)
                .environment(env.info)
                .task {
                    appDelegate.attach(env)
                    await env.bootstrap()
                }
                .onOpenURL { url in
                    env.deepLinks.handle(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { env.deepLinks.handle(url) }
                }
        }
    }
}

/// Делегат приложения: APNs-токен и тапы по уведомлениям о смене статуса заказа.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private var env: AppEnvironment?
    private var pendingToken: Data?
    private var pendingOrderId: Int?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func attach(_ env: AppEnvironment) {
        self.env = env
        if let token = pendingToken {
            env.push.didRegister(deviceToken: token)
            pendingToken = nil
        }
        if let orderId = pendingOrderId {
            env.router.openOrder(id: orderId)
            pendingOrderId = nil
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if let env {
            env.push.didRegister(deviceToken: deviceToken)
        } else {
            pendingToken = deviceToken
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Без подписи с capability Push сюда приходит ошибка — это ожидаемо для сборки из CI.
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let orderId = PushService.orderId(from: notification.request.content.userInfo)
        if orderId != nil {
            await MainActor.run { [weak self] in
                guard let self, let env = self.env else { return }
                Task { await env.orders.load() }
            }
        }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let orderId = PushService.orderId(from: response.notification.request.content.userInfo) else { return }
        await MainActor.run { [weak self] in
            guard let self else { return }
            if let env = self.env {
                env.router.openOrder(id: orderId)
            } else {
                self.pendingOrderId = orderId
            }
        }
    }
}
