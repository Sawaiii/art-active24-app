import Foundation

struct TimeSelection: Codable, Hashable, Sendable {
    let unit: TimeUnit
    let value: Int
}

/// Выбранный доп (`{id, qty}`), qty по умолчанию 1.
struct ExtraSelection: Codable, Hashable, Sendable {
    let id: String
    let qty: Int?

    init(id: String, qty: Int? = nil) {
        self.id = id
        self.qty = qty
    }
}

/// Строка меню с количеством (кейтеринг).
struct MenuSelection: Codable, Hashable, Sendable {
    let id: String
    let qty: Int
}

/// Позиция корзины в том виде, в каком её принимает сервер (`CartItemInput`).
/// Без `complectId` — «строка-опция» (шаблоны simple/showcase): только допы товара, цена = Σ допов × qty.
struct CartItemInput: Codable, Hashable, Sendable {
    var productId: Int
    var complectId: Int?
    var subId: String?
    var priceType: PriceType?
    var time: TimeSelection?
    var qty: Int
    var extras: [ExtraSelection]?
    var menu: [MenuSelection]?

    init(
        productId: Int,
        complectId: Int?,
        subId: String? = nil,
        priceType: PriceType? = nil,
        time: TimeSelection? = nil,
        qty: Int,
        extras: [ExtraSelection]? = nil,
        menu: [MenuSelection]? = nil
    ) {
        self.productId = productId
        self.complectId = complectId
        self.subId = subId
        self.priceType = priceType
        self.time = time
        self.qty = qty
        self.extras = extras
        self.menu = menu
    }
}

struct CartItemsRequest: Encodable, Sendable {
    let items: [CartItemInput]
}

struct QuoteLineExtra: Codable, Hashable, Sendable {
    let name: String?
    let qty: Int?
    let price: Int?
}

/// Строка серверного расчёта корзины.
struct QuoteLine: Codable, Hashable, Identifiable, Sendable {
    let key: String
    let input: CartItemInput
    let productName: String
    let productSlug: String?
    let image: String?
    let art: String?
    let complectTitle: String
    let subTitle: String?
    let priceLabel: String?
    let timeLabel: String?
    let qtyUnit: String?
    let extras: [QuoteLineExtra]?
    let unitPrice: Int
    let total: Int
    let onRequest: Bool?
    let available: Bool
    let warning: String?

    var id: String { key }
}

struct Quote: Codable, Hashable, Sendable {
    let lines: [QuoteLine]
    let total: Int
    let hasOnRequest: Bool?
    let count: Int?
}
