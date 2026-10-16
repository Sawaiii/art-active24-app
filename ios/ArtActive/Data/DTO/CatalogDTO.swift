import Foundation

enum CategoryKind: String, ResilientEnum {
    case catalog, buy, venues, landing, scenario, unknown
    static var unknownCase: CategoryKind { .unknown }
}

/// Узел дерева разделов (меню «Услуги» сайта, 3 уровня).
struct CategoryNode: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let slug: String?
    let url: String?
    let icon: String?
    let image: String?
    let kind: CategoryKind
    let children: [CategoryNode]?

    var childNodes: [CategoryNode] { children ?? [] }
    var hasChildren: Bool { !(children ?? []).isEmpty }
}

/// Карточка-сценарий (лендинг/scenlink) — открывается как веб-страница.
struct Scenario: Codable, Hashable, Sendable {
    let title: String
    let image: String?
    let url: String
}

struct CategoryPage: Codable, Hashable, Sendable {
    let category: CategoryNode
    let title: String?
    let heroVideo: String?
    let breadcrumbs: [Crumb]
    let children: [CategoryNode]
    let scenarios: [Scenario]?
    let seoHtml: String?

    var displayTitle: String { title ?? category.name }
}

enum ProductTemplate: String, ResilientEnum {
    case configurator, simple, showcase, staff, program, unknown
    static var unknownCase: ProductTemplate { .unknown }
}

/// Плитка товара в листинге (`.aa-card`).
struct ProductSummary: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let slug: String
    let name: String
    let image: String?
    let price: PriceTag?
    let badge: Badge?
    let template: ProductTemplate
}

struct ColorFacet: Codable, Hashable, Sendable {
    let name: String?
    let hex: String?
    let count: Int?
}

struct ProductFacets: Codable, Hashable, Sendable {
    let priceMin: Int?
    let priceMax: Int?
    let colors: [ColorFacet]?
}

struct ProductListPayload: Codable, Hashable, Sendable {
    let items: [ProductSummary]?
    let facets: ProductFacets?
}

struct SearchPayload: Codable, Hashable, Sendable {
    let products: [ProductSummary]?
    let categories: [CategoryNode]?
    let correctedQuery: String?
}

enum ResolveTarget: String, ResilientEnum {
    case product, category, venue, web, unknown
    static var unknownCase: ResolveTarget { .unknown }
}

/// Результат разбора ссылки сайта (deep link).
struct ResolvePayload: Codable, Hashable, Sendable {
    let type: ResolveTarget?
    let id: Int?
    let complectId: Int?
    let subId: String?
    let priceType: String?
    let url: String?
}

enum HomeSectionType: String, ResilientEnum {
    case hero, promoTiles, directions, products, cases, benefits, recentlyViewed, unknown
    static var unknownCase: HomeSectionType { .unknown }
}

struct HomeItem: Codable, Hashable, Sendable {
    let title: String?
    let subtitle: String?
    let image: String?
    let video: String?
    let badge: String?
    let categoryId: Int?
    let url: String?
}

struct HomeSection: Codable, Hashable, Sendable {
    let type: HomeSectionType
    let title: String?
    let items: [HomeItem]?
    let products: [ProductSummary]?
}

struct HomePayload: Codable, Hashable, Sendable {
    let sections: [HomeSection]?
}
