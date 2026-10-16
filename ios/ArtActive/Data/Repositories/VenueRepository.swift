import Foundation

/// Фасетный фильтр площадок.
struct VenueQuery: Hashable, Sendable {
    var events: Set<Int> = []
    var types: Set<Int> = []
    var metro: Set<Int> = []
    var props: Set<Int> = []
    var priceFrom: Int?
    var priceTo: Int?
    var capacityFrom: Int?
    var capacityTo: Int?
    var areaFrom: Int?
    var areaTo: Int?
    var collection: Int?

    var activeCount: Int {
        events.count + types.count + metro.count + props.count
            + (priceFrom != nil || priceTo != nil ? 1 : 0)
            + (capacityFrom != nil || capacityTo != nil ? 1 : 0)
            + (areaFrom != nil || areaTo != nil ? 1 : 0)
    }

    func cleared() -> VenueQuery { VenueQuery(collection: collection) }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        func ids(_ set: Set<Int>) -> String? { set.isEmpty ? nil : set.sorted().map(String.init).joined(separator: ",") }
        items.append("events", ids(events))
        items.append("types", ids(types))
        items.append("metro", ids(metro))
        items.append("props", ids(props))
        items.append("priceFrom", priceFrom)
        items.append("priceTo", priceTo)
        items.append("capacityFrom", capacityFrom)
        items.append("capacityTo", capacityTo)
        items.append("areaFrom", areaFrom)
        items.append("areaTo", areaTo)
        items.append("collection", collection)
        return items
    }
}

struct VenueListPage: Sendable {
    let page: Page<VenueSummary>
    let counts: [String: [String: Int]]
}

protocol VenueRepository: Sendable {
    func venues(query: VenueQuery, page: Int) async throws -> VenueListPage
    func filters() async throws -> VenueFiltersPayload
    func venue(id: Int) async throws -> Venue
}

struct LiveVenueRepository: VenueRepository {
    let client: APIClient
    var pageSize = AppConfig.pageSize

    func venues(query: VenueQuery, page: Int) async throws -> VenueListPage {
        var items = query.queryItems
        items.append(URLQueryItem(name: "page", value: String(page)))
        items.append(URLQueryItem(name: "limit", value: String(pageSize)))
        let result = try await client.requestWithMeta(
            .get("/v1/venues", query: items, cacheable: page == 1 && query.activeCount == 0),
            as: VenueListPayload.self
        )
        return VenueListPage(
            page: .make(items: result.value.items ?? [], meta: result.meta, page: page, limit: pageSize),
            counts: result.value.counts ?? [:]
        )
    }

    func filters() async throws -> VenueFiltersPayload {
        try await client.request(.get("/v1/venues/filters", cacheable: true))
    }

    func venue(id: Int) async throws -> Venue {
        try await client.request(.get("/v1/venues/\(id)", cacheable: true))
    }
}
