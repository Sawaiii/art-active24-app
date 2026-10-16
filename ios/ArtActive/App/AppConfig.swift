import Foundation

/// Конфигурация окружения. baseURL берётся из Info.plist (`APIBaseURL` ← build setting `API_BASE_URL`
/// из Config/*.xcconfig): Debug — локальный API, Release — из секрета CI. В коде боевого адреса нет.
enum AppConfig {
    static let apiBaseURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
           let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
           url.scheme != nil, url.host != nil {
            return url
        }
        return placeholderAPI
    }()

    /// Плейсхолдер, если адрес не задан при сборке (запросы завершатся ошибкой сети).
    static let placeholderAPI = URL(string: "https://api.invalid/api/")!
    static var isAPIConfigured: Bool { apiBaseURL.host != placeholderAPI.host }
    static let siteURL = URL(string: "https://www.art-active24.ru")!
    static let siteHosts: Set<String> = ["art-active24.ru", "www.art-active24.ru"]
    static let urlScheme = "artactive24"

    /// Сетевые таймауты (секунды).
    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 60

    /// Пагинация по контракту: limit 1…60, по умолчанию 24.
    static let pageSize = 24
}
