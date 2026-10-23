import Foundation

/// URLProtocol демо-режима: запросы APIClient к `DemoBackend.baseURL` обслуживает встроенный
/// бэкенд, без сети. Подключается только к сессии APIClient (`config.protocolClasses`).
final class DemoURLProtocol: URLProtocol {
    /// Небольшая задержка ответа — чтобы были видны скелетоны, как с настоящим сервером.
    private static let delayRange: ClosedRange<Double> = 0.15...0.35

    private let cancellation = DemoCancellation()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == DemoBackend.baseURL.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let backend = DemoBackend.shared, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let method = request.httpMethod ?? "GET"
        let headers = request.allHTTPHeaderFields ?? [:]
        let body = request.httpBody ?? Self.readAll(request.httpBodyStream)
        let target = DemoProtocolReference(self)
        let cancellation = self.cancellation
        let delay = Double.random(in: Self.delayRange)

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            guard !cancellation.isCancelled else { return }
            let response = backend.handle(method: method, url: url, headers: headers, body: body)
            guard !cancellation.isCancelled, let loader = target.value,
                  let http = HTTPURLResponse(
                      url: url,
                      statusCode: response.status,
                      httpVersion: "HTTP/1.1",
                      headerFields: ["Content-Type": "application/json; charset=utf-8"]
                  ) else { return }
            loader.client?.urlProtocol(loader, didReceive: http, cacheStoragePolicy: .notAllowed)
            if !response.body.isEmpty {
                loader.client?.urlProtocol(loader, didLoad: response.body)
            }
            loader.client?.urlProtocolDidFinishLoading(loader)
        }
    }

    override func stopLoading() {
        cancellation.cancel()
    }

    /// Сессия APIClient для демо-режима.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoURLProtocol.self] + (config.protocolClasses ?? [])
        config.timeoutIntervalForRequest = AppConfig.requestTimeout
        config.timeoutIntervalForResource = AppConfig.resourceTimeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    /// URLSession передаёт тело в протокол потоком — дочитываем целиком.
    private static func readAll(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 16 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Флаг отмены загрузки (stopLoading) — читается из фоновой очереди.
private final class DemoCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Слабая ссылка на загрузчик для фоновой очереди (URLSession сама держит протокол, пока он грузит).
private final class DemoProtocolReference: @unchecked Sendable {
    weak var value: URLProtocol?

    init(_ value: URLProtocol) {
        self.value = value
    }
}
