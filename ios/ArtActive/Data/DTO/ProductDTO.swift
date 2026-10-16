import Foundation

enum PriceType: String, ResilientEnum {
    case rent, buy, unknown
    static var unknownCase: PriceType { .unknown }
}

enum TimeUnit: String, ResilientEnum {
    case hours, days, unknown
    static var unknownCase: TimeUnit { .unknown }
}

enum ConfiguratorMode: String, ResilientEnum {
    case standard, trampoline, cateringMenu, masterclass, unknown
    static var unknownCase: ConfiguratorMode { .unknown }
}

enum OrderMode: String, ResilientEnum {
    case cart, toggle, request, unknown
    static var unknownCase: OrderMode { .unknown }
}

/// Сторона цены комплекта/варианта: аренда или покупка.
struct PriceSide: Codable, Hashable, Sendable {
    let amount: Int
    let label: String
    let postfix: String?
    let from: Bool?
    /// Фиксированная цена — время не применяется.
    let sale: Bool?
    let onRequest: Bool?
    let minQty: Int?
    let qtyStepPct: Double?

    init(
        amount: Int,
        label: String,
        postfix: String? = nil,
        from: Bool? = nil,
        sale: Bool? = nil,
        onRequest: Bool? = nil,
        minQty: Int? = nil,
        qtyStepPct: Double? = nil
    ) {
        self.amount = amount
        self.label = label
        self.postfix = postfix
        self.from = from
        self.sale = sale
        self.onRequest = onRequest
        self.minQty = minQty
        self.qtyStepPct = qtyStepPct
    }
}

/// Правило времени аренды комплекта.
struct TimeRule: Codable, Hashable, Sendable {
    let unit: TimeUnit
    let defaultValue: Int
    /// % от цены за каждый шаг сверх default.
    let percent: Double

    enum CodingKeys: String, CodingKey {
        case unit
        case defaultValue = "default"
        case percent
    }
}

/// Вариант (подкомплект): прибавка к цене комплекта и/или фикс-надбавка.
struct Sub: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let group: String?
    let rent: PriceSide?
    let buy: PriceSide?
    let flatSurcharge: Int?
    let image: String?
    let text: String?

    func side(_ type: PriceType) -> PriceSide? { type == .buy ? buy : rent }
}

/// Строка меню (кейтеринг).
struct MenuRow: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let group: String?
    let name: String
    let price: Int
    let minQty: Int?
}

enum RewardType: String, ResilientEnum {
    case baseFree = "base_free"
    case everyNth = "every_nth"
    case unknown
    static var unknownCase: RewardType { .unknown }
}

struct Reward: Codable, Hashable, Sendable {
    let goal: Int?
    let type: RewardType?
    let label: String?
}

struct Complect: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let title: String
    let subtitle: String?
    let textHtml: String?
    let image: String?
    let pdfUrl: String?
    let rent: PriceSide?
    let buy: PriceSide?
    let time: TimeRule?
    let basePrice: Int?
    let basePriceName: String?
    let subsLabel: String?
    let subs: [Sub]?
    let menu: [MenuRow]?
    let reward: Reward?
    let includes: [String]?
    let requirements: [String]?
    let comment: String?

    func side(_ type: PriceType) -> PriceSide? { type == .buy ? buy : rent }
    var subList: [Sub] { subs ?? [] }
    var menuRows: [MenuRow] { menu ?? [] }
}

/// Доп. опция — «Дополнительные опции» и «Также подходит».
struct Extra: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let price: Int
    let from: Bool?
    let image: String?
    let group: String?
    let required: Bool?
    let note: String?
    let countable: Bool?

    var isRequired: Bool { required == true }
    var isCountable: Bool { countable == true }
}

struct VariantLink: Codable, Hashable, Sendable {
    let complectId: Int?
    let subId: String?
    let priceType: PriceType?
    let slug: String?
    let title: String?
}

struct MasterclassVenue: Codable, Hashable, Sendable {
    let name: String?
    let text: String?
    let images: [String]?
}

struct MasterclassStep: Codable, Hashable, Sendable {
    let title: String?
    let text: String?
}

struct Masterclass: Codable, Hashable, Sendable {
    let variantsLabel: String?
    let priceBadge: String?
    let venueTitle: String?
    let venueText: String?
    let venues: [MasterclassVenue]?
    let stepsTitle: String?
    let steps: [MasterclassStep]?
    let includedTitle: String?
    let included: [String]?
    let relatedTitle: String?
    let related: [ProductSummary]?
    let tags: [Crumb]?
}

enum ContentBlockType: String, ResilientEnum {
    case lead, text, facts, gallery, video, cards, steps, tiers, links, unknown
    static var unknownCase: ContentBlockType { .unknown }
}

struct ContentBlockItem: Codable, Hashable, Sendable {
    let title: String?
    let subtitle: String?
    let text: String?
    let image: String?
    let video: String?
    let price: PriceTag?
    let rows: [Spec]?
    let link: String?
}

/// Типизированный контент-блок шаблонов showcase/staff/program.
struct ContentBlock: Codable, Hashable, Sendable {
    let type: ContentBlockType
    let title: String?
    let text: String?
    let items: [ContentBlockItem]?
}

/// Карточка товара со всеми связями.
struct Product: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let slug: String
    let art: String?
    let name: String
    let template: ProductTemplate
    let configuratorMode: ConfiguratorMode?
    let orderMode: OrderMode
    let categoryId: Int?
    let breadcrumbs: [Crumb]?
    let badge: Badge?
    let media: [MediaItem]
    let price: PriceTag?
    let lead: String?
    let specs: [Spec]?
    let descriptionHtml: String?
    let complectsLabel: String?
    let complects: [Complect]
    let extras: [Extra]
    let similar: [ProductSummary]?
    let variantLinks: [VariantLink]?
    let masterclass: Masterclass?
    let blocks: [ContentBlock]?
    let shareUrl: String?

    var summary: ProductSummary {
        ProductSummary(
            id: id,
            slug: slug,
            name: name,
            image: media.first(where: { $0.type == .image })?.url ?? media.first?.poster,
            price: price,
            badge: badge,
            template: template
        )
    }

    var shareURL: URL? {
        shareUrl?.resolvedURL ?? URL(string: "/\(slug)/", relativeTo: AppConfig.siteURL)?.absoluteURL
    }
}
