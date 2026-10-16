import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Описание запроса к API. Пути — относительно baseURL (`/v1/...`).
struct Endpoint: Sendable {
    enum Auth: Sendable {
        /// Без токена.
        case anonymous
        /// Токен добавляется, если пользователь вошёл (гостю тоже можно).
        case optional
        /// Обязателен; без сессии — `APIError.unauthorized`.
        case required
    }

    var method: HTTPMethod
    var path: String
    var query: [URLQueryItem]
    var body: Data?
    var auth: Auth
    var headers: [String: String]
    /// Ответ кэшируется на диск и отдаётся без сети (каталог, карточки).
    var cacheable: Bool

    init(
        method: HTTPMethod = .get,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        auth: Auth = .anonymous,
        headers: [String: String] = [:],
        cacheable: Bool = false
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.auth = auth
        self.headers = headers
        self.cacheable = cacheable
    }

    static func get(_ path: String, query: [URLQueryItem] = [], auth: Auth = .anonymous, cacheable: Bool = false) -> Endpoint {
        Endpoint(method: .get, path: path, query: query, auth: auth, cacheable: cacheable)
    }

    static func send<Body: Encodable>(
        _ method: HTTPMethod,
        _ path: String,
        body: Body,
        auth: Auth = .anonymous,
        headers: [String: String] = [:]
    ) throws -> Endpoint {
        Endpoint(method: method, path: path, body: try JSONCoding.encode(body), auth: auth, headers: headers)
    }
}

extension Array where Element == URLQueryItem {
    /// Добавляет параметр, только если значение есть.
    mutating func append(_ name: String, _ value: CustomStringConvertible?) {
        guard let value else { return }
        let text = value.description
        guard !text.isEmpty else { return }
        append(URLQueryItem(name: name, value: text))
    }
}
