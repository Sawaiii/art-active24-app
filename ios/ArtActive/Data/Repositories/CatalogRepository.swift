import Foundation

enum ProductSort: String, CaseIterable, Hashable, Sendable {
    case popular
    case priceLow = "price_low"
    case priceHigh = "price_high"
    case new

    var title: String {
        switch self {
        case .popular: return String(localized: "По популярности")
        case .priceLow: return String(localized: "Сначала дешевле")
        case .priceHigh: return String(localized: "Сначала дороже")
        case .new: return String(localized: "Новинки")
        }
    }
}

/// Сортировка и фильтры листинга раздела.
struct ProductQuery: Hashable, Sendable {
    var sort: ProductSort = .popular
    var priceMin: Int?
    var priceMax: Int?
    var colors: Set<String> = []

    /// Число активных фильтров (для бейджа на кнопке).
    var activeFilterCount: Int {
        (priceMin != nil || priceMax != nil ? 1 : 0) + (colors.isEmpty ? 0 : 1)
    }
}

/// Страница списка с признаком «есть ещё».
struct Page<Item: Sendable>: Sendable {
    let items: [Item]
    let page: Int
    let total: Int?
    let hasMore: Bool

    static func make(items: [Item], meta: PageMeta?, page: Int, limit: Int) -> Page<Item> {
        let total = meta?.total
        let hasMore: Bool
        if let total {
            hasMore = page * limit < total
        } else {
            hasMore = items.count >= limit
        }
        return Page(items: items, page: page, total: total, hasMore: hasMore)
    }
}

struct ProductListPage: Sendable {
    let page: Page<ProductSummary>
    let facets: ProductFacets?
}

struct SearchResult: Sendable {
    let products: Page<ProductSummary>
    let categories: [CategoryNode]
    let correctedQuery: String?
}

protocol CatalogRepository: Sendable {
    func home() async throws -> HomePayload
    func tree() async throws -> [CategoryNode]
    func category(id: Int) async throws -> CategoryPage
    func products(categoryId: Int, query: ProductQuery, page: Int) async throws -> ProductListPage
    func product(id: Int) async throws -> Product
    func search(_ text: String, page: Int) async throws -> SearchResult
    func resolve(path: String) async throws -> ResolvePayload
}

struct LiveCatalogRepository: CatalogRepository {
    let client: APIClient
    var pageSize = AppConfig.pageSize

    func home() async throws -> HomePayload {
        try await client.request(.get("/v1/home", cacheable: true))
    }

    func tree() async throws -> [CategoryNode] {
        try await client.request(.get("/v1/catalog/tree", cacheable: true))
    }

    func category(id: Int) async throws -> CategoryPage {
        try await client.request(.get("/v1/categories/\(id)", cacheable: true))
    }

    func products(categoryId: Int, query: ProductQuery, page: Int) async throws -> ProductListPage {
        var items: [URLQueryItem] = [URLQueryItem(name: "sort", value: query.sort.rawValue)]
        items.append("priceMin", query.priceMin)
        items.append("priceMax", query.priceMax)
        if !query.colors.isEmpty {
            items.append(URLQueryItem(name: "colors", value: query.colors.sorted().joined(separator: ",")))
        }
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "limit", value: String(pageSize)))
        let result = try await client.requestWithMeta(
            .get("/v1/categories/\(categoryId)/products", query: items, cacheable: page == 1),
            as: ProductListPayload.self
        )
        return ProductListPage(
            page: .make(items: result.value.items ?? [], meta: result.meta, page: page, limit: pageSize),
            facets: result.value.facets
        )
    }

    func product(id: Int) async throws -> Product {
        try await client.request(.get("/v1/products/\(id)", cacheable: true))
    }

    func search(_ text: String, page: Int) async throws -> SearchResult {
        let query = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(pageSize)),
        ]
        let result = try await client.requestWithMeta(.get("/v1/search", query: query), as: SearchPayload.self)
        return SearchResult(
            products: .make(items: result.value.products ?? [], meta: result.meta, page: page, limit: pageSize),
            categories: result.value.categories ?? [],
            correctedQuery: result.value.correctedQuery
        )
    }

    func resolve(path: String) async throws -> ResolvePayload {
        try await client.request(.get("/v1/resolve", query: [URLQueryItem(name: "path", value: path)]))
    }
}
