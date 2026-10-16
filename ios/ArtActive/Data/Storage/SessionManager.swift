import Foundation

/// Хранит access/refresh-токены (Keychain) и обновляет их без гонок:
/// параллельные запросы ждут один и тот же refresh.
actor SessionManager {
    struct Tokens: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date

        init(session: AuthSession, now: Date = Date()) {
            accessToken = session.accessToken
            refreshToken = session.refreshToken
            expiresAt = now.addingTimeInterval(TimeInterval(max(session.expiresIn, 0)))
        }
    }

    typealias Refresher = @Sendable (_ refreshToken: String) async throws -> AuthSession

    private static let account = "tokens"
    /// Обновляем заранее, чтобы токен не протух в полёте.
    private static let expiryLeeway: TimeInterval = 30

    private let keychain: KeychainStore
    private var tokens: Tokens?
    private var refreshTask: Task<Tokens, Error>?

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        if let data = keychain.data(for: Self.account) {
            tokens = try? JSONCoding.makeDecoder().decode(Tokens.self, from: data)
        }
    }

    var hasSession: Bool { tokens != nil }

    func store(_ session: AuthSession) {
        let new = Tokens(session: session)
        tokens = new
        persist(new)
    }

    func clear() {
        tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
        keychain.remove(Self.account)
    }

    /// Действующий access-токен (обновляется при необходимости) или nil, если сессии нет.
    func validAccessToken(refresher: @escaping Refresher) async throws -> String? {
        guard let current = tokens else { return nil }
        if current.expiresAt.timeIntervalSinceNow > Self.expiryLeeway {
            return current.accessToken
        }
        return try await refresh(refresher: refresher).accessToken
    }

    /// Принудительное обновление (после 401).
    func forceRefresh(refresher: @escaping Refresher) async throws -> String {
        try await refresh(refresher: refresher).accessToken
    }

    private func refresh(refresher: @escaping Refresher) async throws -> Tokens {
        if let running = refreshTask {
            return try await running.value
        }
        guard let current = tokens else { throw APIError.unauthorized }
        let refreshToken = current.refreshToken
        let task = Task<Tokens, Error> {
            let session = try await refresher(refreshToken)
            return Tokens(session: session)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let new = try await task.value
            tokens = new
            persist(new)
            return new
        } catch let error as APIError where error == .unauthorized || error.statusCode == 401 || error.statusCode == 400 {
            // Разлогиниваем только если сервер отверг refresh (400/401).
            // Сеть, 5xx, 429, 403 — сессию сохраняем, ошибка уходит выше.
            clear()
            throw APIError.unauthorized
        }
    }

    private func persist(_ tokens: Tokens) {
        guard let data = try? JSONCoding.makeEncoder().encode(tokens) else { return }
        keychain.set(data, for: Self.account)
    }
}
