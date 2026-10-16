import Foundation
import OSLog

/// Конверт ответа `{success, data, error, meta?}`.
struct Envelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIErrorPayload?
    let meta: PageMeta?
}

/// Ответ без полезных данных (для разбора ошибок).
private struct ErrorEnvelope: Decodable {
    let success: Bool?
    let error: APIErrorPayload?
}

/// Единый HTTP-клиент: конверт, ошибки, токены с авто-refresh, офлайн-кэш GET.
final class APIClient: @unchecked Sendable {
    private let baseURL: URL
    private let urlSession: URLSession
    private let cache: ResponseCache
    let sessionManager: SessionManager
    private let logger = Logger(subsystem: "ru.artactive24.app", category: "api")

    /// Вызывается, если сессию восстановить не удалось (refresh отклонён).
    private let unauthorizedHandler = UnauthorizedHandlerBox()

    init(
        baseURL: URL = AppConfig.apiBaseURL,
        sessionManager: SessionManager,
        cache: ResponseCache = ResponseCache(),
        urlSession: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.sessionManager = sessionManager
        self.cache = cache
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = AppConfig.requestTimeout
            config.timeoutIntervalForResource = AppConfig.resourceTimeout
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.urlSession = URLSession(configuration: config)
        }
    }

    func setUnauthorizedHandler(_ handler: @escaping @Sendable () async -> Void) async {
        await unauthorizedHandler.set(handler)
    }

    // MARK: - Public API

    func request<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> T {
        try await requestWithMeta(endpoint, as: type).value
    }

    func requestWithMeta<T: Decodable>(_ endpoint: Endpoint, as type: T.Type = T.self) async throws -> (value: T, meta: PageMeta?) {
        let cacheKey = endpoint.cacheable ? try makeRequest(endpoint).url?.absoluteString : nil
        do {
            let (data, status) = try await perform(endpoint)
            let result = try decode(T.self, data: data, status: status)
            if let cacheKey, (200..<300).contains(status) {
                cache.store(data, for: cacheKey)
            }
            return result
        } catch let error as APIError where error.isConnectivity {
            if let cacheKey, let cached = cache.data(for: cacheKey),
               let result = try? decode(T.self, data: cached, status: 200) {
                logger.info("Offline: отдан кэш для \(cacheKey, privacy: .public)")
                return result
            }
            throw error
        }
    }

    /// Запрос, ответ которого не нужен (204 или любой 2xx).
    func send(_ endpoint: Endpoint) async throws {
        let (data, status) = try await perform(endpoint)
        guard (200..<300).contains(status) else {
            throw errorFrom(data: data, status: status)
        }
    }

    // MARK: - Transport

    private func perform(_ endpoint: Endpoint, allowRefresh: Bool = true) async throws -> (Data, Int) {
        var request = try makeRequest(endpoint)

        if endpoint.auth != .anonymous {
            let token: String?
            do {
                token = try await sessionManager.validAccessToken(refresher: refresher)
            } catch APIError.unauthorized {
                // Сервер отверг refresh (400/401) — сессия уже очищена.
                await unauthorizedHandler.call()
                throw APIError.unauthorized
            }
            if let token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            } else if endpoint.auth == .required {
                throw APIError.unauthorized
            }
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw Self.map(transportError: error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        // 401 на обычный запрос → один refresh и повтор. Разлогин — только если отверг сам
        // /v1/auth/refresh (400/401); сеть/5xx/429 при refresh — сессия сохраняется.
        if http.statusCode == 401, endpoint.auth != .anonymous, allowRefresh, await sessionManager.hasSession {
            do {
                _ = try await sessionManager.forceRefresh(refresher: refresher)
            } catch APIError.unauthorized {
                await unauthorizedHandler.call()
                throw APIError.unauthorized
            }
            return try await perform(endpoint, allowRefresh: false)
        }
        return (data, http.statusCode)
    }

    private var refresher: SessionManager.Refresher {
        { [weak self] refreshToken in
            guard let self else { throw APIError.cancelled }
            return try await self.refreshSession(refreshToken: refreshToken)
        }
    }

    private func refreshSession(refreshToken: String) async throws -> AuthSession {
        let endpoint = try Endpoint.send(.post, "/v1/auth/refresh", body: RefreshRequest(refreshToken: refreshToken))
        let request = try makeRequest(endpoint)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw Self.map(transportError: error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        return try decode(AuthSession.self, data: data, status: http.statusCode).value
    }

    private func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        let trimmed = endpoint.path.hasPrefix("/") ? String(endpoint.path.dropFirst()) : endpoint.path
        let url = baseURL.appendingPathComponent(trimmed)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }
        guard let finalURL = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: finalURL)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    // MARK: - Decoding

    private func decode<T: Decodable>(_ type: T.Type, data: Data, status: Int) throws -> (value: T, meta: PageMeta?) {
        guard (200..<300).contains(status) else {
            throw errorFrom(data: data, status: status)
        }
        let envelope: Envelope<T>
        do {
            envelope = try JSONCoding.makeDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            logger.error("Decoding \(String(describing: T.self), privacy: .public) failed: \(String(describing: error), privacy: .public)")
            throw APIError.decoding(String(describing: error))
        }
        if let payload = envelope.error, !envelope.success {
            throw APIError.server(status: status, code: payload.code, message: payload.message, fields: payload.fields ?? [:])
        }
        guard let value = envelope.data else {
            throw APIError.decoding("Пустое поле data для \(T.self)")
        }
        return (value, envelope.meta)
    }

    private func errorFrom(data: Data, status: Int) -> APIError {
        if let envelope = try? JSONCoding.makeDecoder().decode(ErrorEnvelope.self, from: data),
           let payload = envelope.error {
            return .server(status: status, code: payload.code, message: payload.message, fields: payload.fields ?? [:])
        }
        if status == 401 { return .unauthorized }
        return .http(status: status)
    }

    private static func map(transportError error: Error) -> APIError {
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .invalidResponse }
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        default:
            return .http(status: urlError.errorCode)
        }
    }

    /// Язык интерфейса приложения (ru/en) — сервер отдаёт тексты на нём, если умеет.
    private static let acceptLanguage: String = {
        let languages = Bundle.main.preferredLocalizations.filter { $0 != "Base" }
        return (languages.isEmpty ? ["ru"] : languages).prefix(2).joined(separator: ", ")
    }()

    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "ArtActive-iOS/\(version)"
    }()
}

/// Потокобезопасное хранилище обработчика «сессия потеряна».
private actor UnauthorizedHandlerBox {
    private var handler: (@Sendable () async -> Void)?

    func set(_ handler: @escaping @Sendable () async -> Void) {
        self.handler = handler
    }

    func call() async {
        await handler?()
    }
}
