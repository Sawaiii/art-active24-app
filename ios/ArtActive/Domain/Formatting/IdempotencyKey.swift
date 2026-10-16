import CryptoKit
import Foundation

/// Idempotency-Key для POST /v1/orders и /v1/requests.
/// Ключ привязан к хешу тела: изменилось тело — новый ключ. После окончательного ответа
/// (успех или ошибка 4xx) ключ сбрасывается; после сетевой ошибки или 5xx — сохраняется,
/// чтобы повтор не создал дубль заказа.
struct IdempotencyKey {
    private var current: String?
    private var bodyHash: String?

    mutating func key<Body: Encodable>(for body: Body) -> String {
        let hash = Self.hash(body)
        if let current, hash == bodyHash { return current }
        let fresh = UUID().uuidString
        current = fresh
        bodyHash = hash
        return fresh
    }

    /// Вызывается после ответа: `error == nil` — успех.
    mutating func finish(error: Error?) {
        if let api = error as? APIError {
            if api.isConnectivity || api == .cancelled { return }
            if let status = api.statusCode, status >= 500 { return }
        }
        current = nil
        bodyHash = nil
    }

    private static func hash<Body: Encodable>(_ body: Body) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(body) else { return UUID().uuidString }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
