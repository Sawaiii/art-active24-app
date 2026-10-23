import Foundation

/// Статусы заказа (контракт `OrderStatus`).
enum OrderStatus: String, ResilientEnum, CaseIterable {
    case processing
    case confirmed
    case preparing
    case delivering
    case inProgress = "in_progress"
    case completed
    case cancelled
    case unknown

    static var unknownCase: OrderStatus { .unknown }

    /// Локальная подпись, если сервер не прислал `statusLabel`.
    var title: String {
        switch self {
        case .processing: return String(localized: "В обработке")
        case .confirmed: return String(localized: "Подтверждён")
        case .preparing: return String(localized: "Комплектуется")
        case .delivering: return String(localized: "В пути")
        case .inProgress: return String(localized: "Мероприятие идёт")
        case .completed: return String(localized: "Завершён")
        case .cancelled: return String(localized: "Отменён")
        case .unknown: return String(localized: "Статус уточняется")
        }
    }

    /// Порядок «счастливого пути» для таймлайна.
    static let timeline: [OrderStatus] = [.processing, .confirmed, .preparing, .delivering, .inProgress, .completed]
}

enum DeliveryMethod: String, ResilientEnum {
    case delivery, pickup, unknown
    static var unknownCase: DeliveryMethod { .unknown }
}

enum OrderKind: String, ResilientEnum {
    case cart, product, venue, callback, unknown
    static var unknownCase: OrderKind { .unknown }
}

enum RequestKind: String, Codable, Sendable {
    case product, venue, callback
}

struct CheckoutDelivery: Codable, Hashable, Sendable {
    let method: DeliveryMethod
    let address: String?
}

struct CheckoutRequest: Encodable, Sendable {
    let items: [CartItemInput]
    /// `YYYY-MM-DD`
    let eventDate: String
    let eventDateTo: String?
    let delivery: CheckoutDelivery
    let contactName: String?
    let contactPhone: String?
    let comment: String?
}

/// Заявка без корзины (персонал, программа, площадка, звонок).
struct RequestCreate: Encodable, Sendable {
    let kind: RequestKind
    let productId: Int?
    let complectId: Int?
    let venueId: Int?
    let eventDate: String?
    let eventType: String?
    let guests: Int?
    let comment: String?
}

struct OrderDelivery: Codable, Hashable, Sendable {
    let method: DeliveryMethod?
    let address: String?
}

struct OrderLine: Codable, Hashable, Sendable {
    let productId: Int?
    let productName: String?
    let productSlug: String?
    let image: String?
    let art: String?
    let complectTitle: String?
    let subTitle: String?
    let timeLabel: String?
    let qty: Int?
    let qtyUnit: String?
    let extras: [QuoteLineExtra]?
    let unitPrice: Int?
    let total: Int?
    let onRequest: Bool?
    let input: CartItemInput?
}

struct StatusEvent: Codable, Hashable, Sendable {
    let status: OrderStatus?
    let label: String?
    let at: Date?
    let comment: String?
}

struct Order: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let number: String
    let kind: OrderKind
    let status: OrderStatus
    let statusLabel: String
    let createdAt: Date
    let updatedAt: Date?
    let eventDate: String?
    let eventDateTo: String?
    let delivery: OrderDelivery?
    let contactName: String?
    let contactPhone: String?
    let comment: String?
    let subject: String?
    let lines: [OrderLine]
    let total: Int
    let hasOnRequest: Bool?
    let canCancel: Bool?
    let history: [StatusEvent]
    // Личный кабинет (необязательные поля контракта; старый сервер их не присылает).
    var userId: Int?
    /// Сумма позиций до скидки (есть, только если была скидка).
    var subtotal: Int?
    var discount: PriceDiscount?
    /// Доступна машина на карте (`GET /v1/orders/{id}/vehicle`).
    var tracking: Bool?
    var canReview: Bool?
    var review: OrderReview?
    var canClaim: Bool?
    var claims: [OrderClaim]?

    /// Позиции, которые можно положить в корзину повторно.
    var repeatableItems: [CartItemInput] { lines.compactMap(\.input) }
    var lastChange: Date { updatedAt ?? history.compactMap(\.at).max() ?? createdAt }
}
