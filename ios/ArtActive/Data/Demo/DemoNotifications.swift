import Foundation
import UserNotifications

/// Уведомления о смене статусов демо-заявок (вместо push от сервера).
protocol DemoOrderNotifier: Sendable {
    func scheduleStatusChanges(for order: DemoOrder)
    func cancelStatusChanges(orderId: Int)
    func removeAll()
}

/// Локальные уведомления: планируются, только если пользователь разрешил уведомления.
/// Тап открывает заказ так же, как push (`userInfo.orderId`, см. AppDelegate).
struct DemoLocalNotifier: DemoOrderNotifier {
    private static let prefix = "demo-order-"

    func scheduleStatusChanges(for order: DemoOrder) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                let center = UNUserNotificationCenter.current()
                for request in Self.requests(for: order, now: Date()) { center.add(request) }
            default:
                break
            }
        }
    }

    func cancelStatusChanges(orderId: Int) {
        let ids = DemoOrderTimeline.steps.map { Self.identifier(orderId: orderId, status: $0.status) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func removeAll() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private static func identifier(orderId: Int, status: OrderStatus) -> String {
        "\(prefix)\(orderId)-\(status.rawValue)"
    }

    private static func requests(for order: DemoOrder, now: Date) -> [UNNotificationRequest] {
        DemoOrderTimeline.steps.compactMap { step -> UNNotificationRequest? in
            let fireAt = order.createdAt.addingTimeInterval(step.offset)
            let interval = fireAt.timeIntervalSince(now)
            guard step.offset > 0, interval > 0 else { return nil }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Заявка \(order.number)")
            content.body = step.status == .confirmed
                ? "\(step.status.title). \(DemoOrderTimeline.confirmedComment)"
                : step.status.title
            content.sound = .default
            content.userInfo = ["type": "order", "orderId": order.id]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
            return UNNotificationRequest(identifier: identifier(orderId: order.id, status: step.status), content: content, trigger: trigger)
        }
    }
}
