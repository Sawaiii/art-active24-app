import Foundation
import os

/// Текущий адрес API. Обычно это адрес из сборки (`AppConfig.apiBaseURL`). Если в сборке задан
/// `API_CONFIG_URL`, при запуске адрес подтягивается из удалённого конфига — так тестовые сборки
/// работают с временным сервером, адрес которого меняется, без пересборки приложения.
/// Последний полученный адрес запоминается и используется до следующего обновления.
final class APIBaseURLStore: @unchecked Sendable {
    static let shared = APIBaseURLStore()

    private static let defaultsKey = "api.remoteBaseURL"
    private static let fetchTimeout: TimeInterval = 6

    private let lock = NSLock()
    private var current: URL
    private let logger = Logger(subsystem: "ru.artactive24.app", category: "config")

    private init() {
        let cached = UserDefaults.standard.string(forKey: Self.defaultsKey).flatMap(Self.validURL)
        current = (AppConfig.apiConfigURL != nil ? cached : nil) ?? AppConfig.apiBaseURL
    }

    var url: URL {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    var isConfigured: Bool { url.host != AppConfig.placeholderAPI.host }

    /// Обновить адрес из удалённого конфига (если он задан в сборке). Ошибки не критичны:
    /// остаётся прежний адрес.
    func refreshFromRemote() async {
        guard let configURL = AppConfig.apiConfigURL else { return }
        var request = URLRequest(url: configURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.fetchTimeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let raw = Self.extractBaseURL(from: data),
                  let url = Self.validURL(raw) else {
                logger.error("Удалённый конфиг API без корректного адреса")
                return
            }
            store(url)
        } catch {
            logger.error("Удалённый конфиг API недоступен: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Синхронно: `NSLock` нельзя брать прямо в async-контексте.
    private func store(_ url: URL) {
        lock.lock()
        current = url
        lock.unlock()
        UserDefaults.standard.set(url.absoluteString, forKey: Self.defaultsKey)
    }

    /// Поддерживаются два формата: `{"apiBaseURL": "…"}` и ответ GitHub Gist API
    /// (`files.*.content` с тем же JSON внутри).
    static func extractBaseURL(from data: Data) -> String? {
        struct Config: Decodable { let apiBaseURL: String }
        struct Gist: Decodable {
            struct File: Decodable { let content: String? }
            let files: [String: File]
        }
        let decoder = JSONDecoder()
        if let config = try? decoder.decode(Config.self, from: data) {
            return config.apiBaseURL
        }
        guard let gist = try? decoder.decode(Gist.self, from: data) else { return nil }
        for file in gist.files.values.sorted(by: { ($0.content ?? "") < ($1.content ?? "") }) {
            if let content = file.content?.data(using: .utf8),
               let config = try? decoder.decode(Config.self, from: content) {
                return config.apiBaseURL
            }
        }
        return nil
    }

    /// Только https и только с хостом — подменить адрес на что-то кроме HTTPS-сервера нельзя.
    static func validURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
