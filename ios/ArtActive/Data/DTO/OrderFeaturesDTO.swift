import Foundation

// Личный кабинет заказа: скидка, состав из КП, машина на карте, отзыв, претензия, документы,
// программа лояльности (contract/openapi.yaml — Discount, OrderComposition, VehicleLocation,
// OrderReview, OrderClaim, OrderDocument, Loyalty).

// MARK: - Скидка

enum DiscountKind: String, ResilientEnum {
    case loyalty, promo, manual, unknown
    static var unknownCase: DiscountKind { .unknown }
}

/// Скидка к сумме позиций («Скидка постоянного клиента −5%»). amount — рубли, положительное число.
struct PriceDiscount: Codable, Hashable, Sendable {
    let kind: DiscountKind?
    let title: String
    let percent: Int?
    let amount: Int
}

// MARK: - Состав заказа

enum CompositionSource: String, ResilientEnum {
    case kp, manager, cart
    /// «none» в контракте: состава ещё нет (заявка без корзины).
    case empty = "none"
    case unknown
    static var unknownCase: CompositionSource { .unknown }
}

struct CompositionLine: Codable, Hashable, Sendable {
    let name: String
    let art: String?
    let qty: Double
    let unit: String
    let days: Int?
    let price: Int
    let sum: Int
    let note: String?
    let onRequest: Bool?
}

struct CompositionSection: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let lines: [CompositionLine]
    let subtotal: Int
}

struct OrderComposition: Codable, Hashable, Sendable {
    let source: CompositionSource
    let kpNumber: String?
    /// `YYYY-MM-DD`
    let kpDate: String?
    let version: Int
    let updatedAt: Date?
    let title: String?
    let sections: [CompositionSection]
    let subtotal: Int
    let discounts: [PriceDiscount]?
    /// nil — стоимость доставки рассчитает менеджер.
    let delivery: Int?
    let deliveryNote: String?
    let total: Int
    let vatNote: String?
    let hasOnRequest: Bool?

    var isEmpty: Bool { sections.allSatisfy { $0.lines.isEmpty } }
}

// MARK: - Машина на карте

enum VehicleStatus: String, ResilientEnum {
    case enRoute, arrived, unknown
    static var unknownCase: VehicleStatus { .unknown }
}

enum VehicleSource: String, ResilientEnum {
    case driver, tracker, unknown
    static var unknownCase: VehicleSource { .unknown }
}

struct VehicleLocation: Codable, Hashable, Sendable {
    let status: VehicleStatus
    let lat: Double?
    let lng: Double?
    /// Радиус точности, м.
    let accuracy: Double?
    /// Курс, градусы.
    let heading: Double?
    /// Время последней достоверной точки.
    let updatedAt: Date?
    let eta: Date?
    let source: VehicleSource?
    let vehicle: String?
    let driverName: String?

    /// Есть координаты, которые можно показать на карте.
    var hasFix: Bool { lat != nil && lng != nil }
}

// MARK: - Отзыв

struct OrderReview: Codable, Hashable, Sendable {
    let rating: Int
    let text: String?
    let createdAt: Date
    let updatedAt: Date?
    let editableUntil: Date?
    let canEdit: Bool?
}

struct ReviewInput: Encodable, Sendable {
    let rating: Int
    let text: String?
}

// MARK: - Претензия

enum ClaimCategory: String, ResilientEnum {
    case late, quality, incomplete, staff, other, unknown
    static var unknownCase: ClaimCategory { .unknown }

    /// Варианты для формы (без `unknown`).
    static let selectable: [ClaimCategory] = [.late, .quality, .incomplete, .staff, .other]

    var title: String {
        switch self {
        case .late: return String(localized: "Опоздание")
        case .quality: return String(localized: "Качество")
        case .incomplete: return String(localized: "Комплектность")
        case .staff: return String(localized: "Персонал")
        case .other, .unknown: return String(localized: "Другое")
        }
    }

    var symbol: String {
        switch self {
        case .late: return "clock.badge.exclamationmark"
        case .quality: return "hand.thumbsdown"
        case .incomplete: return "shippingbox"
        case .staff: return "person.2"
        case .other, .unknown: return "ellipsis.bubble"
        }
    }
}

enum ClaimStatus: String, ResilientEnum {
    case submitted, accepted, resolved, rejected, unknown
    static var unknownCase: ClaimStatus { .unknown }

    var title: String {
        switch self {
        case .submitted: return String(localized: "Отправлена")
        case .accepted: return String(localized: "Принята")
        case .resolved: return String(localized: "Решена")
        case .rejected: return String(localized: "Отклонена")
        case .unknown: return String(localized: "Статус уточняется")
        }
    }

    var isOpen: Bool { self == .submitted || self == .accepted }
}

enum ContactPreference: String, ResilientEnum {
    case call, messenger, email, unknown
    static var unknownCase: ContactPreference { .unknown }

    static let selectable: [ContactPreference] = [.call, .messenger, .email]

    var title: String {
        switch self {
        case .call, .unknown: return String(localized: "Позвонить")
        case .messenger: return String(localized: "Написать в мессенджер")
        case .email: return String(localized: "Ответить на почту")
        }
    }
}

struct ClaimPhoto: Codable, Hashable, Sendable {
    let url: String
}

struct OrderClaim: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let orderId: Int
    let orderNumber: String?
    let category: ClaimCategory
    let categoryLabel: String?
    let description: String
    let contactPreference: ContactPreference?
    let photos: [ClaimPhoto]?
    let status: ClaimStatus
    let statusLabel: String?
    let managerComment: String?
    /// https-ссылка на чат «Жалобы» в Вызов Чате (после «Принята»).
    let chatUrl: String?
    /// Та же ссылка для приложения: `vyzovchat://join/<token>`.
    let chatAppUrl: String?
    let createdAt: Date
    let updatedAt: Date?
}

struct ClaimInput: Encodable, Sendable {
    let category: ClaimCategory
    let description: String
    let contactPreference: ContactPreference
    let photos: [ClaimPhoto]?
}

// MARK: - Документы

enum DocumentKind: String, ResilientEnum {
    case contract, act, invoice, kp, other, unknown
    static var unknownCase: DocumentKind { .unknown }

    var title: String {
        switch self {
        case .contract: return String(localized: "Договор")
        case .act: return String(localized: "Акт")
        case .invoice: return String(localized: "Счёт")
        case .kp: return String(localized: "Коммерческое предложение")
        case .other, .unknown: return String(localized: "Документ")
        }
    }

    var symbol: String {
        switch self {
        case .contract: return "signature"
        case .act: return "checkmark.seal"
        case .invoice: return "rublesign.circle"
        case .kp: return "list.bullet.rectangle"
        case .other, .unknown: return "doc"
        }
    }
}

enum DocumentSource: String, ResilientEnum {
    case crm, vyzovchat, manager, unknown
    static var unknownCase: DocumentSource { .unknown }

    var title: String {
        switch self {
        case .crm: return String(localized: "CRM")
        case .vyzovchat: return String(localized: "Вызов Чат")
        case .manager, .unknown: return String(localized: "Менеджер")
        }
    }
}

struct OrderDocument: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let kind: DocumentKind
    let source: DocumentSource
    /// `YYYY-MM-DD`
    let date: String?
    let url: String
    /// Байт.
    let size: Int?
    let mime: String?
}

// MARK: - Программа лояльности

struct LoyaltyTier: Codable, Hashable, Sendable {
    let level: Int?
    let threshold: Int
    let percent: Int
}

struct LoyaltyNextTier: Codable, Hashable, Sendable {
    let level: Int?
    let percent: Int
    let threshold: Int
    let remaining: Int
}

/// Персональная скидка от менеджера — важнее уровня.
struct LoyaltyOverride: Codable, Hashable, Sendable {
    let percent: Int
    let note: String?
}

enum LoyaltySource: String, ResilientEnum {
    case tier
    case personal = "override"
    case unknown
    static var unknownCase: LoyaltySource { .unknown }
}

struct Loyalty: Codable, Hashable, Sendable {
    /// Действующая скидка, %.
    let percent: Int
    let source: LoyaltySource?
    let tier: LoyaltyTier
    /// Сумма завершённых заказов за всё время, ₽.
    let spent: Int
    let completedOrders: Int?
    let nextTier: LoyaltyNextTier?
    let tiers: [LoyaltyTier]
    /// Поле `override` контракта.
    let personal: LoyaltyOverride?

    enum CodingKeys: String, CodingKey {
        case percent, source, tier, spent, completedOrders, nextTier, tiers
        case personal = "override"
    }

    /// Доля пути от текущего порога до следующего (0…1); на максимальном уровне — 1.
    var progressToNext: Double {
        guard let next = nextTier, next.threshold > tier.threshold else { return 1 }
        let done = Double(spent - tier.threshold) / Double(next.threshold - tier.threshold)
        return min(max(done, 0), 1)
    }
}

// MARK: - Заказ: удобные признаки

extension Order {
    /// Машину можно показать на карте (статус «В пути»).
    var isTracking: Bool { tracking ?? (status == .delivering) }
    /// Открытая претензия (отправлена или принята).
    var activeClaim: OrderClaim? { claims?.first { $0.status.isOpen } ?? claims?.first }
}
