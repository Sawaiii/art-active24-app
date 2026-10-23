import Foundation

/// Документы заказа: скачать во временный файл для QuickLook и «Поделиться».
/// В демо-режиме документы с адреса демо-бэкенда рисуются на телефоне (`DemoDocumentPDF`) — без сети.
/// MainActor: вызывается из экранов, а отрисовка демо-PDF — UIKit; сама загрузка не блокирует поток.
@MainActor
enum DocumentLoader {
    private static let quickLookExtensions: Set<String> = ["pdf", "png", "jpg", "jpeg", "heic", "doc", "docx", "xls", "xlsx", "txt", "rtf"]
    /// Защита от «документа» на сотни мегабайт.
    private static let maxBytes: Int64 = 50 * 1024 * 1024

    /// Файл можно показать в QuickLook (иначе — веб-страница в Safari View).
    static func prefersQuickLook(_ document: OrderDocument) -> Bool {
        if let mime = document.mime?.lowercased(), mime == "application/pdf" || mime.hasPrefix("image/") { return true }
        guard let url = URL(string: document.url) else { return false }
        if isDemo(url) { return true }
        return quickLookExtensions.contains(url.pathExtension.lowercased())
    }

    static func localFile(for document: OrderDocument) async throws -> URL {
        guard let url = URL(string: document.url) else { throw URLError(.badURL) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("order-documents", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(fileName(for: document, url: url))

        if isDemo(url) {
            guard let data = DemoDocumentPDF.render(title: document.title, kind: document.kind, date: document.date) else {
                throw URLError(.fileDoesNotExist)
            }
            try data.write(to: destination, options: .atomic)
            return destination
        }
        guard url.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        if http.expectedContentLength > maxBytes { throw URLError(.dataLengthExceedsMaximum) }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    private static func isDemo(_ url: URL) -> Bool {
        url.host == DemoBackend.baseURL.host
    }

    /// Имя файла из названия документа (его видит получатель «Поделиться»).
    private static func fileName(for document: OrderDocument, url: URL) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.newlines).union(.controlCharacters)
        let base = document.title.components(separatedBy: forbidden).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let name = base.isEmpty ? "document" : String(base.prefix(80))
        var ext = url.pathExtension.lowercased()
        if ext.isEmpty || !quickLookExtensions.contains(ext) {
            ext = document.mime?.lowercased().hasPrefix("image/") == true ? "jpg" : "pdf"
        }
        return "\(name).\(ext)"
    }
}
