import Foundation
import OSLog

/// Небольшие несекретные данные приложения в Application Support (JSON-файлы):
/// гостевая корзина, избранное, «Вы смотрели», история поиска, кэш профиля.
struct LocalStore: Sendable {
    enum Key: String, Sendable {
        case cart
        case favorites
        case recentlyViewed = "recently-viewed"
        case searchHistory = "search-history"
        case user
        case seenOrders = "seen-orders"
    }

    private let directory: URL

    init(folder: String = "store") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ type: T.Type, key: Key) -> T? {
        let url = fileURL(key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONCoding.makeDecoder().decode(T.self, from: data)
        } catch {
            Logger(subsystem: "ru.artactive24.app", category: "store")
                .error("Повреждён файл \(key.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    func save<T: Encodable>(_ value: T, key: Key) {
        do {
            let data = try JSONCoding.makeEncoder().encode(value)
            try data.write(to: fileURL(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Logger(subsystem: "ru.artactive24.app", category: "store")
                .error("Не сохранён \(key.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func remove(_ key: Key) {
        try? FileManager.default.removeItem(at: fileURL(key))
    }

    private func fileURL(_ key: Key) -> URL {
        directory.appendingPathComponent(key.rawValue).appendingPathExtension("json")
    }
}
