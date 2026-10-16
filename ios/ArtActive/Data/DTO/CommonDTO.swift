import Foundation

/// Строковый enum, который не роняет декодирование при новом значении с сервера:
/// неизвестное значение превращается в `unknownCase`.
protocol ResilientEnum: RawRepresentable, Codable, Hashable, Sendable where RawValue == String {
    static var unknownCase: Self { get }
}

extension ResilientEnum {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Self(rawValue: raw) ?? Self.unknownCase
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// `meta` конверта для списков.
struct PageMeta: Codable, Hashable, Sendable {
    let total: Int?
    let page: Int?
    let limit: Int?
}

/// Медиа товара (фото/видео).
struct MediaItem: Codable, Hashable, Sendable {
    enum Kind: String, ResilientEnum {
        case image, video, unknown
        static var unknownCase: Kind { .unknown }
    }

    let type: Kind
    let url: String
    let poster: String?

    var resolvedURL: URL? { url.resolvedURL }
    var posterURL: URL? { poster?.resolvedURL }
}

/// Бейдж «Хит», «Новинка!».
struct Badge: Codable, Hashable, Sendable {
    let text: String
    let color: String?
}

/// Готовая к показу цена в листинге.
struct PriceTag: Codable, Hashable, Sendable {
    let amount: Int?
    let from: Bool?
    let unit: String?
    let onRequest: Bool?

    init(amount: Int?, from: Bool? = nil, unit: String? = nil, onRequest: Bool? = nil) {
        self.amount = amount
        self.from = from
        self.unit = unit
        self.onRequest = onRequest
    }
}

/// Хлебная крошка / тег (`{id, name}`).
struct Crumb: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
}

/// Характеристика «имя — значение».
struct Spec: Codable, Hashable, Sendable {
    let name: String
    let value: String
}

struct GeoPoint: Codable, Hashable, Sendable {
    let lat: Double?
    let lng: Double?
}

extension String {
    /// URL из строки контракта (`format: uri`). Пустые и относительные пути
    /// разрешаются относительно сайта, мусор — nil (а не падение декодирования).
    var resolvedURL: URL? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        if trimmed.hasPrefix("//") { return URL(string: "https:" + trimmed) }
        return URL(string: trimmed, relativeTo: AppConfig.siteURL)?.absoluteURL
    }
}
