import CryptoKit
import Foundation

/// Офлайн-кэш JSON-ответов каталога (последний успешный ответ на каждый URL).
/// Лежит в Caches — система может очистить, это нормально.
final class ResponseCache: @unchecked Sendable {
    private let directory: URL
    private let queue = DispatchQueue(label: "ru.artactive24.response-cache")

    init(folder: String = "api-cache") {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent(folder, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func store(_ data: Data, for key: String) {
        let url = fileURL(for: key)
        queue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    func data(for key: String) -> Data? {
        let url = fileURL(for: key)
        return queue.sync { try? Data(contentsOf: url) }
    }

    func removeAll() {
        let dir = directory
        queue.async {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func fileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }
}
