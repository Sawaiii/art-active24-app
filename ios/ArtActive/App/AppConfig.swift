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
    static var isAPIConfigured: Bool { APIBaseURLStore.shared.isConfigured }

    /// Удалённый конфиг с актуальным адресом API (только тестовые сборки с временным сервером;
    /// задаётся секретом CI `API_CONFIG_URL`). Пусто — адрес берётся только из сборки.
    static let apiConfigURL: URL? = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIConfigURL") as? String else { return nil }
        return APIBaseURLStore.validURL(raw)
    }()
    /// Демо-режим: встроенный каталог и бэкенд (DemoBackend), без сервера. Включён, если в сборке
    /// `DEMO_MODE = YES` (Release по умолчанию) или адрес API не задан и нет удалённого конфига.
    static let isDemoMode: Bool = {
        let flag = (Bundle.main.object(forInfoDictionaryKey: "DemoMode") as? String)?
            .trimmingCharacters(in: .whitespaces).uppercased()
        if flag == "YES" { return true }
        return apiBaseURL.host == placeholderAPI.host && apiConfigURL == nil
    }()

    static let siteURL = URL(string: "https://www.art-active24.ru")!
    static let siteHosts: Set<String> = ["art-active24.ru", "www.art-active24.ru"]
    static let urlScheme = "artactive24"

    /// Сетевые таймауты (секунды).
    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 60

    /// Пагинация по контракту: limit 1…60, по умолчанию 24.
    static let pageSize = 24
}
