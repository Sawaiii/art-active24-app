import Foundation

struct MetroStation: Codable, Hashable, Sendable {
    let name: String?
    let color: String?
    /// Метры до станции.
    let distance: Int?
}

struct VenueSummary: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let slug: String
    let name: String
    let type: String?
    let photos: [String]?
    let area: Int?
    let capacity: Int?
    let address: String?
    let metro: [MetroStation]?
    let price: PriceTag?
}

/// Карточка площадки (`VenueSummary` + подробности; в контракте — allOf).
struct Venue: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let slug: String
    let name: String
    let type: String?
    let photos: [String]?
    let area: Int?
    let capacity: Int?
    let address: String?
    let metro: [MetroStation]?
    let price: PriceTag?
    let minHours: Int?
    let descriptionHtml: String?
    let howToRent: [String]?
    let geo: GeoPoint?
    let eventTypes: [String]?
    let similar: [VenueSummary]?
    let shareUrl: String?

    var shareURL: URL? {
        shareUrl?.resolvedURL ?? URL(string: "/\(slug)/", relativeTo: AppConfig.siteURL)?.absoluteURL
    }
}

struct VenueListPayload: Codable, Hashable, Sendable {
    let items: [VenueSummary]?
    /// Счётчики фасетов: группа → (id опции → кол-во).
    let counts: [String: [String: Int]]?
}

struct FilterOption: Codable, Hashable, Sendable {
    let id: Int?
    let name: String?
    let group: String?
    let color: String?
    let count: Int?
}

struct RangeBounds: Codable, Hashable, Sendable {
    let min: Int?
    let max: Int?
}

struct VenueFiltersPayload: Codable, Hashable, Sendable {
    let events: [FilterOption]?
    let types: [FilterOption]?
    let metro: [FilterOption]?
    let props: [FilterOption]?
    let ranges: [String: RangeBounds]?
}
