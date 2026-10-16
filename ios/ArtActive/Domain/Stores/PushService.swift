import Foundation
import Observation
import UIKit
import UserNotifications

/// Push (APNs): разрешение, токен устройства → `/v1/me/devices`.
/// Без подписи с capability Push токен не выдаётся — сервис просто молчит.
@MainActor
@Observable
final class PushService {
    private(set) var deviceToken: String?
    private(set) var isAuthorized = false

    @ObservationIgnored private let repository: ProfileRepository
    @ObservationIgnored private let isLoggedIn: @MainActor () -> Bool
    @ObservationIgnored private var registeredToken: String?

    init(repository: ProfileRepository, isLoggedIn: @escaping @MainActor () -> Bool) {
        self.repository = repository
        self.isLoggedIn = isLoggedIn
    }

    /// Спрашиваем разрешение в осмысленный момент — после входа или первого заказа.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            isAuthorized = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        case .authorized, .provisional, .ephemeral:
            isAuthorized = true
        default:
            isAuthorized = false
        }
        if isAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await registerIfPossible() }
    }

    func registerIfPossible() async {
        guard isLoggedIn(), let token = deviceToken, token != registeredToken else { return }
        do {
            try await repository.registerDevice(token: token)
            registeredToken = token
        } catch {
            // Повторим при следующем запуске/входе.
        }
    }

    /// Снять токен с сервера — вызывается ДО /v1/auth/logout, пока сессия жива.
    func unregister() async {
        guard let token = registeredToken ?? deviceToken else { return }
        try? await repository.unregisterDevice(token: token)
        registeredToken = nil
    }

    func handleSignOut() {
        registeredToken = nil
    }

    /// id заказа из payload push-уведомления (`orderId` числом или строкой).
    nonisolated static func orderId(from userInfo: [AnyHashable: Any]) -> Int? {
        if let id = userInfo["orderId"] as? Int { return id }
        if let raw = userInfo["orderId"] as? String { return Int(raw) }
        if let number = userInfo["orderId"] as? NSNumber { return number.intValue }
        return nil
    }
}
