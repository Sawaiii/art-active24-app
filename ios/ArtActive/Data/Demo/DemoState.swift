import Foundation

/// Пользователь демо-бэкенда.
struct DemoUser: Codable, Sendable {
    let id: Int
    let phone: String
    var name: String?
    var email: String?
    var company: String?

    var dto: User { User(id: id, phone: phone, name: name, email: email, company: company, role: .customer) }
}

struct DemoSession: Codable, Sendable {
    let userId: Int
    var accessToken: String
    var refreshToken: String
}

/// Заявка: статус не хранится — он вычисляется по времени создания (симуляция менеджера).
struct DemoOrder: Codable, Sendable {
    let id: Int
    let userId: Int
    let number: String
    let kind: OrderKind
    let idempotencyKey: String
    let createdAt: Date
    var cancelledAt: Date?
    let eventDate: String?
    let eventDateTo: String?
    let delivery: OrderDelivery?
    let contactName: String?
    let contactPhone: String?
    let comment: String?
    let subject: String?
    let lines: [OrderLine]
    /// Итог к оплате (после скидки постоянного клиента).
    let total: Int
    let hasOnRequest: Bool
    // Необязательные — старый файл состояния без них читается (decodeIfPresent синтезированного Codable).
    /// Сумма позиций до скидки (только если скидка была).
    var subtotal: Int?
    /// Скидка постоянного клиента на момент оформления, %.
    var discountPercent: Int?
}

/// Отзыв клиента о мероприятии (один на заказ, правка — 7 дней).
struct DemoReview: Codable, Sendable {
    let orderId: Int
    var rating: Int
    var text: String?
    let createdAt: Date
    var updatedAt: Date?
}

/// Претензия «Что-то пошло не так»: статус вычисляется по времени (симуляция менеджера).
struct DemoClaim: Codable, Sendable {
    let id: Int
    let orderId: Int
    let userId: Int
    let category: ClaimCategory
    let description: String
    let contactPreference: ContactPreference
    let photos: [ClaimPhoto]
    let createdAt: Date
}

/// Всё, что демо-бэкенд хранит на телефоне (Application Support/demo-backend.json).
struct DemoState: Codable, Sendable {
    var users: [DemoUser] = []
    var sessions: [DemoSession] = []
    var carts: [String: [CartItemInput]] = [:]
    var favorites: [String: [Int]] = [:]
    var orders: [DemoOrder] = []
    var nextUserId = 1
    var nextOrderId = 1
    /// Отзывы по id заказа (строкой — ключ JSON).
    var reviews: [String: DemoReview] = [:]
    var claims: [DemoClaim] = []
    var nextClaimId = 1

    enum CodingKeys: String, CodingKey {
        case users, sessions, carts, favorites, orders, nextUserId, nextOrderId, reviews, claims, nextClaimId
    }
}

extension DemoState {
    /// Файл, сохранённый прошлой версией приложения (без отзывов и претензий), читается без потерь.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        users = try container.decodeIfPresent([DemoUser].self, forKey: .users) ?? []
        sessions = try container.decodeIfPresent([DemoSession].self, forKey: .sessions) ?? []
        carts = try container.decodeIfPresent([String: [CartItemInput]].self, forKey: .carts) ?? [:]
        favorites = try container.decodeIfPresent([String: [Int]].self, forKey: .favorites) ?? [:]
        orders = try container.decodeIfPresent([DemoOrder].self, forKey: .orders) ?? []
        nextUserId = try container.decodeIfPresent(Int.self, forKey: .nextUserId) ?? 1
        nextOrderId = try container.decodeIfPresent(Int.self, forKey: .nextOrderId) ?? 1
        reviews = try container.decodeIfPresent([String: DemoReview].self, forKey: .reviews) ?? [:]
        claims = try container.decodeIfPresent([DemoClaim].self, forKey: .claims) ?? []
        nextClaimId = try container.decodeIfPresent(Int.self, forKey: .nextClaimId) ?? 1
    }
}

/// Чтение и запись состояния (атомарно, только из-под блокировки бэкенда).
struct DemoStateStore: Sendable {
    let fileURL: URL?

    static var live: DemoStateStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return DemoStateStore(fileURL: base.appendingPathComponent("demo-backend.json"))
    }

    /// Без файла — состояние только в памяти (тесты).
    static let memory = DemoStateStore(fileURL: nil)

    func load() -> DemoState {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let state = try? JSONCoding.makeDecoder().decode(DemoState.self, from: data) else { return DemoState() }
        return state
    }

    func save(_ state: DemoState) {
        guard let fileURL, let data = try? JSONCoding.makeEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Симуляция менеджера: статус двигается от времени создания заявки.
enum DemoOrderTimeline {
    struct Step: Sendable {
        let status: OrderStatus
        let offset: TimeInterval
    }

    static let steps: [Step] = [
        Step(status: .processing, offset: 0),
        Step(status: .confirmed, offset: 40),
        Step(status: .preparing, offset: 120),
        Step(status: .delivering, offset: 240),
        Step(status: .inProgress, offset: 360),
        Step(status: .completed, offset: 480),
    ]

    static let confirmedComment = "Наличие подтверждено, менеджер свяжется для деталей доставки"

    static func createdComment(_ kind: OrderKind) -> String {
        kind == .cart
            ? "Заявка принята. Менеджер свяжется с вами для подтверждения"
            : "Заявка принята. Менеджер свяжется с вами"
    }

    static func history(of order: DemoOrder, now: Date) -> [StatusEvent] {
        let limit = order.cancelledAt.map { min($0, now) } ?? now
        var events: [StatusEvent] = []
        for step in steps {
            let at = order.createdAt.addingTimeInterval(step.offset)
            guard at <= limit else { break }
            let comment: String?
            switch step.status {
            case .processing: comment = createdComment(order.kind)
            case .confirmed: comment = confirmedComment
            default: comment = nil
            }
            events.append(StatusEvent(status: step.status, label: step.status.title, at: at, comment: comment))
        }
        if let cancelledAt = order.cancelledAt, cancelledAt <= now {
            events.append(StatusEvent(status: .cancelled, label: OrderStatus.cancelled.title, at: cancelledAt, comment: "Отменена клиентом"))
        }
        return events
    }

    static func status(of order: DemoOrder, now: Date) -> OrderStatus {
        history(of: order, now: now).last?.status ?? .processing
    }

    static func present(_ order: DemoOrder, now: Date) -> Order {
        let events = history(of: order, now: now)
        let status = events.last?.status ?? .processing
        return Order(
            id: order.id,
            number: order.number,
            kind: order.kind,
            status: status,
            statusLabel: status.title,
            createdAt: order.createdAt,
            updatedAt: events.last?.at ?? order.createdAt,
            eventDate: order.eventDate,
            eventDateTo: order.eventDateTo,
            delivery: order.delivery,
            contactName: order.contactName,
            contactPhone: order.contactPhone,
            comment: order.comment,
            subject: order.subject,
            lines: order.lines,
            total: order.total,
            hasOnRequest: order.hasOnRequest,
            canCancel: status == .processing,
            history: events
        )
    }
}
