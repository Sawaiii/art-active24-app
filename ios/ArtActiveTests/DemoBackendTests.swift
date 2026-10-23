import XCTest
@testable import ArtActive

/// Встроенный демо-бэкенд: набор DemoData из бандла приложения (host app), состояние в памяти,
/// подменяемые часы.
final class DemoBackendTests: XCTestCase {
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var current: Date

        init(_ date: Date) { current = date }

        var now: Date {
            lock.lock()
            defer { lock.unlock() }
            return current
        }

        func advance(_ seconds: TimeInterval) {
            lock.lock()
            current = current.addingTimeInterval(seconds)
            lock.unlock()
        }
    }

    private var clock: TestClock!
    private var backend: DemoBackend!

    override func setUpWithError() throws {
        let dataset = try XCTUnwrap(DemoDataset.bundled(Bundle.main), "Набор DemoData не встроен в бандл приложения")
        let clock = TestClock(Date())
        self.clock = clock
        backend = DemoBackend(dataset: dataset, store: .memory, notifier: nil, clock: { clock.now })
    }

    // MARK: - Помощники

    private func call(
        _ method: String,
        _ path: String,
        body: Any? = nil,
        token: String? = nil,
        headers: [String: String] = [:]
    ) -> DemoResponse {
        let url = try! XCTUnwrap(URL(string: path, relativeTo: DemoBackend.baseURL)?.absoluteURL)
        var allHeaders = headers
        if let token { allHeaders["Authorization"] = "Bearer \(token)" }
        let data = body.map { try! JSONSerialization.data(withJSONObject: $0) }
        return backend.handle(method: method, url: url, headers: allHeaders, body: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ response: DemoResponse, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        let envelope = try JSONCoding.makeDecoder().decode(Envelope<T>.self, from: response.body)
        return try XCTUnwrap(envelope.data, "Пустой data (статус \(response.status))", file: file, line: line)
    }

    private func signIn() throws -> String {
        XCTAssertEqual(call("POST", "v1/auth/code", body: ["phone": "+79001234567"]).status, 200)
        let wrong = call("POST", "v1/auth/verify", body: ["phone": "+79001234567", "code": "111111"])
        XCTAssertEqual(wrong.status, 422, "неверный код")
        let session = try decode(AuthSession.self, call("POST", "v1/auth/verify", body: ["phone": "+79001234567", "code": DemoBackend.demoCode]))
        return session.accessToken
    }

    private static func tomorrow(after date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        let next = calendar.date(byAdding: .day, value: 2, to: date) ?? date
        let parts = calendar.dateComponents([.year, .month, .day], from: next)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2030, parts.month ?? 1, parts.day ?? 1)
    }

    private static let viktoriaItem: [String: Any] = [
        "productId": 7138, "complectId": 1724, "priceType": "rent",
        "time": ["unit": "days", "value": 2], "qty": 2,
    ]

    // MARK: - Каталог

    func testTreeHasSeventeenRoots() throws {
        let tree = try decode([CategoryNode].self, call("GET", "v1/catalog/tree"))
        XCTAssertEqual(tree.count, 17)
        XCTAssertTrue(tree.contains { $0.hasChildren }, "у корней есть подразделы")
    }

    func testSearchTrampolineIsNotEmpty() throws {
        let response = call("GET", "v1/search?q=%D0%B1%D0%B0%D1%82%D1%83%D1%82") // «батут»
        let result = try decode(SearchPayload.self, response)
        XCTAssertFalse(result.products?.isEmpty ?? true)
        let empty = call("GET", "v1/search?q=a")
        XCTAssertEqual(empty.status, 422, "минимум 2 символа")
    }

    func testColorFilterIsCanonical() throws {
        // «Чёрный» и «Черный» — один цвет фильтра.
        let response = call("GET", "v1/categories/225/products?colors=%D0%A7%D1%91%D1%80%D0%BD%D1%8B%D0%B9") // «Чёрный»
        let list = try decode(ProductListPayload.self, response)
        XCTAssertFalse(list.items?.isEmpty ?? true, "товары с цветом «Черный» находятся по «Чёрный»")
        let names = list.facets?.colors?.compactMap(\.name) ?? []
        XCTAssertTrue(names.contains("Черный"))
        XCTAssertFalse(names.contains("Чёрный"), "в фасетах только каноническое название")
        XCTAssertEqual(Set(names).count, names.count, "без дублей")
    }

    // MARK: - Акции и кейсы

    func testSaleAlwaysAnswers() throws {
        let sale = try decode(SalePayload.self, call("GET", "v1/sale"))
        XCTAssertFalse((sale.title ?? "").isEmpty, "без sale.json — заголовок по умолчанию и пустой список")
        XCTAssertEqual(call("POST", "v1/sale").status, 404)
    }

    func testCasesListDetailAndHomeTiles() throws {
        guard backend.dataset.raw("cases.json") != nil else { throw XCTSkip("В наборе DemoData ещё нет кейсов") }
        let list = try decode(CaseListPayload.self, call("GET", "v1/cases"))
        let first = try XCTUnwrap(list.items?.first, "список кейсов не пуст")
        let study = try decode(CaseStudy.self, call("GET", "v1/cases/\(first.slug)"))
        XCTAssertEqual(study.slug, first.slug)
        XCTAssertFalse(study.media?.isEmpty ?? true, "у кейса есть фото")
        XCTAssertEqual(call("GET", "v1/cases/no-such-case-404").status, 404)
        XCTAssertEqual(call("GET", "v1/cases?category=abc").status, 422)

        if let categoryId = list.categories?.first?.id {
            let filtered = try decode(CaseListPayload.self, call("GET", "v1/cases?category=\(categoryId)"))
            XCTAssertTrue(filtered.items?.allSatisfy { $0.categoryId == categoryId } ?? false)
        }

        // Плитка кейса со slug на главной открывается в приложении.
        let home = try decode(HomePayload.self, call("GET", "v1/home"))
        for item in home.sections?.first(where: { $0.type == .cases })?.items ?? [] {
            guard let slug = item.slug else { continue }
            XCTAssertEqual(call("GET", "v1/cases/\(slug)").status, 200, slug)
        }

        let resolved = try decode(ResolvePayload.self, call("GET", "v1/resolve?path=/cases/\(first.slug)/"))
        XCTAssertEqual(resolved.type, .caseStudy)
        XCTAssertEqual(resolved.slug, first.slug)
    }

    func testProductAndMissingProduct() throws {
        let product = try decode(Product.self, call("GET", "v1/products/7138"))
        XCTAssertEqual(product.id, 7138)
        XCTAssertEqual(call("GET", "v1/products/999999999").status, 404)
    }

    // MARK: - Корзина

    func testQuoteViktoriaTwoDaysTimesTwo() throws {
        let quote = try decode(Quote.self, call("POST", "v1/cart/quote", body: ["items": [Self.viktoriaItem]]))
        XCTAssertEqual(quote.total, 1848)
        let line = try XCTUnwrap(quote.lines.first)
        XCTAssertTrue(line.available)
        XCTAssertEqual(line.unitPrice, 924)
        XCTAssertEqual(line.timeLabel, "2 д")
        XCTAssertEqual(line.qtyUnit, "шт")
    }

    func testQuoteMarksUnavailableAndValidates() throws {
        let quote = try decode(Quote.self, call("POST", "v1/cart/quote", body: ["items": [
            ["productId": 7138, "complectId": 999_999, "qty": 1],
        ]]))
        XCTAssertEqual(quote.lines.first?.available, false)
        XCTAssertEqual(quote.total, 0)
        let invalid = call("POST", "v1/cart/quote", body: ["items": [["productId": 7138, "qty": 1]]])
        XCTAssertEqual(invalid.status, 422, "без комплекта и допов — ошибка поля")
    }

    // MARK: - Заявки

    func testCheckoutCreatesProcessingOrderThatGetsConfirmed() throws {
        let token = try signIn()
        let body: [String: Any] = [
            "items": [Self.viktoriaItem],
            "eventDate": Self.tomorrow(after: clock.now),
            "delivery": ["method": "delivery", "address": "Москва, Лужники, 24"],
            "contactName": "Анна",
        ]
        let missingKey = call("POST", "v1/orders", body: body, token: token)
        XCTAssertEqual(missingKey.status, 400, "без Idempotency-Key")

        let created = call("POST", "v1/orders", body: body, token: token, headers: ["Idempotency-Key": "demo-key-0001"])
        XCTAssertEqual(created.status, 201)
        let order = try decode(Order.self, created)
        XCTAssertEqual(order.status, .processing)
        XCTAssertEqual(order.number, "AA-000001")
        XCTAssertEqual(order.total, 1848)
        XCTAssertEqual(order.canCancel, true)

        let repeated = try decode(Order.self, call("POST", "v1/orders", body: body, token: token, headers: ["Idempotency-Key": "demo-key-0001"]))
        XCTAssertEqual(repeated.id, order.id, "тот же ключ — та же заявка")

        clock.advance(41)
        let confirmed = try decode(Order.self, call("GET", "v1/orders/\(order.id)", token: token))
        XCTAssertEqual(confirmed.status, .confirmed)
        XCTAssertEqual(confirmed.history.count, 2)
        XCTAssertEqual(confirmed.canCancel, false)
        XCTAssertEqual(call("POST", "v1/orders/\(order.id)/cancel", token: token).status, 409, "отмена — только в обработке")

        clock.advance(500)
        let completed = try decode([Order].self, call("GET", "v1/orders", token: token))
        XCTAssertEqual(completed.first?.status, .completed)
    }

    func testCheckoutValidation() throws {
        let token = try signIn()
        let past = call("POST", "v1/orders", body: [
            "items": [Self.viktoriaItem],
            "eventDate": "2000-01-01",
            "delivery": ["method": "pickup"],
        ], token: token, headers: ["Idempotency-Key": "demo-key-0002"])
        XCTAssertEqual(past.status, 422)

        let noAddress = call("POST", "v1/orders", body: [
            "items": [Self.viktoriaItem],
            "eventDate": Self.tomorrow(after: clock.now),
            "delivery": ["method": "delivery"],
        ], token: token, headers: ["Idempotency-Key": "demo-key-0003"])
        XCTAssertEqual(noAddress.status, 422)

        let changed = call("POST", "v1/orders", body: [
            "items": [["productId": 7138, "complectId": 999_999, "qty": 1]],
            "eventDate": Self.tomorrow(after: clock.now),
            "delivery": ["method": "pickup"],
        ], token: token, headers: ["Idempotency-Key": "demo-key-0004"])
        XCTAssertEqual(changed.status, 409, "cart_changed")
    }

    func testCancelWhileProcessing() throws {
        let token = try signIn()
        let created = call("POST", "v1/requests", body: ["kind": "callback"], token: token, headers: ["Idempotency-Key": "demo-key-0005"])
        let order = try decode(Order.self, created)
        XCTAssertEqual(order.kind, .callback)
        let cancelled = try decode(Order.self, call("POST", "v1/orders/\(order.id)/cancel", token: token))
        XCTAssertEqual(cancelled.status, .cancelled)
        clock.advance(600)
        let later = try decode(Order.self, call("GET", "v1/orders/\(order.id)", token: token))
        XCTAssertEqual(later.status, .cancelled, "отменённая заявка дальше не двигается")
    }

    func testAuthRequired() {
        XCTAssertEqual(call("GET", "v1/orders").status, 401)
        XCTAssertEqual(call("GET", "v1/me", token: "unknown").status, 401)
    }
}
