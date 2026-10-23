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
        XCTAssertEqual(order.subtotal, 1848)
        XCTAssertEqual(order.total, 1811, "демо-клиент сразу на уровне 2 %: 1848 − 37")
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
        XCTAssertEqual(call("GET", "v1/me/loyalty").status, 401)
        XCTAssertEqual(call("GET", "v1/orders/1/vehicle").status, 401)
    }

    // MARK: - Личный кабинет заказа

    private func checkoutViktoria(_ token: String, key: String) throws -> Order {
        let body: [String: Any] = [
            "items": [Self.viktoriaItem],
            "eventDate": Self.tomorrow(after: clock.now),
            "delivery": ["method": "delivery", "address": "Москва, Лужники, 24"],
        ]
        let response = call("POST", "v1/orders", body: body, token: token, headers: ["Idempotency-Key": key])
        XCTAssertEqual(response.status, 201)
        return try decode(Order.self, response)
    }

    private func order(_ id: Int, _ token: String) throws -> Order {
        try decode(Order.self, call("GET", "v1/orders/\(id)", token: token))
    }

    private func errorCode(_ response: DemoResponse) -> String? {
        let json = DemoJSON.parse(response.body) as? [String: Any]
        return (json?["error"] as? [String: Any])?["code"] as? String
    }

    func testLoyaltyBaselineDiscountsQuoteCartAndCheckout() throws {
        let token = try signIn()
        let loyalty = try decode(Loyalty.self, call("GET", "v1/me/loyalty", token: token))
        XCTAssertEqual(loyalty.percent, 2)
        XCTAssertEqual(loyalty.spent, DemoLoyalty.baselineSpent)
        XCTAssertEqual(loyalty.tier.level, 2)
        XCTAssertEqual(loyalty.nextTier?.percent, 3)
        XCTAssertEqual(loyalty.nextTier?.remaining, 150_000 - DemoLoyalty.baselineSpent)
        XCTAssertEqual(loyalty.tiers.count, 9)
        XCTAssertEqual(loyalty.completedOrders, DemoLoyalty.baselineOrders)

        let guest = try decode(Quote.self, call("POST", "v1/cart/quote", body: ["items": [Self.viktoriaItem]]))
        XCTAssertEqual(guest.total, 1848)
        XCTAssertNil(guest.subtotal, "гостю скидки нет")
        XCTAssertNil(guest.discount)

        let bad = try decode(Quote.self, call("POST", "v1/cart/quote", body: ["items": [Self.viktoriaItem]], token: "expired"))
        XCTAssertNil(bad.discount, "неверный токен — как гость, без ошибки")

        let mine = try decode(Quote.self, call("POST", "v1/cart/quote", body: ["items": [Self.viktoriaItem]], token: token))
        XCTAssertEqual(mine.subtotal, 1848)
        XCTAssertEqual(mine.discount?.amount, 37, "floor(1848 × 2 / 100 + 0.5)")
        XCTAssertEqual(mine.discount?.percent, 2)
        XCTAssertEqual(mine.discount?.kind, .loyalty)
        XCTAssertEqual(mine.discount?.title, "Скидка постоянного клиента \u{2212}2%")
        XCTAssertEqual(mine.total, 1811)
        XCTAssertEqual(mine.lines.first?.total, 1848, "цены строк скидка не меняет")

        let cart = try decode(Quote.self, call("PUT", "v1/cart", body: ["items": [Self.viktoriaItem]], token: token))
        XCTAssertEqual(cart.total, 1811)

        let order = try checkoutViktoria(token, key: "demo-loyal-01")
        XCTAssertEqual(order.subtotal, 1848)
        XCTAssertEqual(order.discount?.amount, 37)
        XCTAssertEqual(order.total, 1811)
        XCTAssertEqual(order.userId, 1)

        clock.advance(481)
        let after = try decode(Loyalty.self, call("GET", "v1/me/loyalty", token: token))
        XCTAssertEqual(after.spent, DemoLoyalty.baselineSpent + 1811, "завершённый заказ входит в сумму")
        XCTAssertEqual(after.completedOrders, DemoLoyalty.baselineOrders + 1)
    }

    func testVehicleOnlyWhileDelivering() throws {
        let token = try signIn()
        let order = try checkoutViktoria(token, key: "demo-car-0001")
        let early = call("GET", "v1/orders/\(order.id)/vehicle", token: token)
        XCTAssertEqual(early.status, 409)
        XCTAssertEqual(errorCode(early), "tracking_unavailable")

        clock.advance(250)
        XCTAssertEqual(try self.order(order.id, token).tracking, true)
        let first = try decode(VehicleLocation.self, call("GET", "v1/orders/\(order.id)/vehicle", token: token))
        XCTAssertEqual(first.status, .enRoute)
        XCTAssertTrue(first.hasFix)
        XCTAssertNotNil(first.eta)
        XCTAssertTrue((12...40).contains(first.accuracy ?? 0))
        XCTAssertTrue((0..<360).contains(first.heading ?? -1))

        clock.advance(50)
        let second = try decode(VehicleLocation.self, call("GET", "v1/orders/\(order.id)/vehicle", token: token))
        XCTAssertTrue(first.lat != second.lat || first.lng != second.lng, "машина едет")

        clock.advance(60)
        XCTAssertEqual(call("GET", "v1/orders/\(order.id)/vehicle", token: token).status, 409, "мероприятие идёт — карты нет")
        XCTAssertEqual(try self.order(order.id, token).tracking, false)
    }

    func testCompositionFromCartThenKpAfterConfirmation() throws {
        let token = try signIn()
        let order = try checkoutViktoria(token, key: "demo-comp-001")
        let cart = try decode(OrderComposition.self, call("GET", "v1/orders/\(order.id)/composition", token: token))
        XCTAssertEqual(cart.source, .cart)
        XCTAssertEqual(cart.version, 1)
        XCTAssertFalse(cart.sections.isEmpty)
        XCTAssertEqual(cart.sections.reduce(0) { $0 + $1.subtotal }, cart.subtotal)
        XCTAssertEqual(cart.subtotal, 1848)
        XCTAssertEqual(cart.total, order.total)
        XCTAssertEqual(cart.sections.first?.lines.first?.days, 2)

        clock.advance(41)
        let kp = try decode(OrderComposition.self, call("GET", "v1/orders/\(order.id)/composition", token: token))
        XCTAssertEqual(kp.source, .kp)
        XCTAssertEqual(kp.version, 2)
        XCTAssertEqual(kp.kpNumber, "КП-2026-0001")
        XCTAssertNotNil(kp.kpDate)
        let logistics = try XCTUnwrap(kp.sections.first { $0.title == "Логистика" })
        XCTAssertEqual(logistics.subtotal, 5500)
        XCTAssertEqual(kp.subtotal, 1848 + 5500)
        XCTAssertEqual(kp.total, kp.subtotal - (kp.discounts?.first?.amount ?? 0))

        let request = try decode(Order.self, call("POST", "v1/requests", body: ["kind": "callback"], token: token, headers: ["Idempotency-Key": "demo-comp-002"]))
        let none = try decode(OrderComposition.self, call("GET", "v1/orders/\(request.id)/composition", token: token))
        XCTAssertEqual(none.source, .empty)
        XCTAssertTrue(none.sections.isEmpty)
    }

    func testDocumentsAppearByStatus() throws {
        let token = try signIn()
        let order = try checkoutViktoria(token, key: "demo-docs-001")
        XCTAssertTrue(try decode([OrderDocument].self, call("GET", "v1/orders/\(order.id)/documents", token: token)).isEmpty)

        clock.advance(41)
        let confirmed = try decode([OrderDocument].self, call("GET", "v1/orders/\(order.id)/documents", token: token))
        XCTAssertEqual(Set(confirmed.map(\.kind)), [.kp, .contract])

        clock.advance(330)
        XCTAssertEqual(try decode([OrderDocument].self, call("GET", "v1/orders/\(order.id)/documents", token: token)).count, 3)

        clock.advance(120)
        let all = try decode([OrderDocument].self, call("GET", "v1/orders/\(order.id)/documents", token: token))
        XCTAssertEqual(all.count, 5)
        XCTAssertTrue(all.contains { $0.kind == .invoice && $0.source == .crm })
        XCTAssertTrue(all.allSatisfy { URL(string: $0.url)?.host == DemoBackend.baseURL.host && $0.mime == "application/pdf" })
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "id уникальны")
    }

    func testReviewAfterCompletionEditableForSevenDays() throws {
        let token = try signIn()
        let order = try checkoutViktoria(token, key: "demo-review-1")
        let early = call("POST", "v1/orders/\(order.id)/review", body: ["rating": 5], token: token)
        XCTAssertEqual(early.status, 409)
        XCTAssertEqual(errorCode(early), "review_unavailable")
        XCTAssertEqual(try self.order(order.id, token).canReview, false)

        clock.advance(481)
        XCTAssertEqual(try self.order(order.id, token).canReview, true)
        XCTAssertEqual(call("POST", "v1/orders/\(order.id)/review", body: ["rating": 6], token: token).status, 422)

        let created = call("POST", "v1/orders/\(order.id)/review", body: ["rating": 5, "text": "  Всё отлично  "], token: token)
        XCTAssertEqual(created.status, 201)
        let review = try decode(OrderReview.self, created)
        XCTAssertEqual(review.rating, 5)
        XCTAssertEqual(review.text, "Всё отлично")
        XCTAssertEqual(review.canEdit, true)

        let edited = call("POST", "v1/orders/\(order.id)/review", body: ["rating": 4], token: token)
        XCTAssertEqual(edited.status, 200)
        XCTAssertEqual(try decode(OrderReview.self, edited).rating, 4)
        XCTAssertEqual(try self.order(order.id, token).review?.rating, 4)

        clock.advance(7 * 86_400 + 1)
        let locked = call("POST", "v1/orders/\(order.id)/review", body: ["rating": 3], token: token)
        XCTAssertEqual(locked.status, 409)
        XCTAssertEqual(errorCode(locked), "review_locked")
        XCTAssertEqual(try self.order(order.id, token).canReview, false)
    }

    func testClaimWindowAutoAcceptAndLimit() throws {
        let token = try signIn()
        let order = try checkoutViktoria(token, key: "demo-claim-01")
        let body: [String: Any] = ["category": "late", "description": "Машина опоздала на два часа", "contactPreference": "messenger"]
        let early = call("POST", "v1/orders/\(order.id)/claims", body: body, token: token)
        XCTAssertEqual(early.status, 409)
        XCTAssertEqual(errorCode(early), "claim_unavailable")

        clock.advance(361)
        XCTAssertEqual(try self.order(order.id, token).canClaim, true)
        XCTAssertEqual(call("POST", "v1/orders/\(order.id)/claims", body: ["category": "late", "description": "Плохо"], token: token).status, 422)
        XCTAssertEqual(call("POST", "v1/orders/\(order.id)/claims", body: ["category": "bad", "description": "Машина опоздала на два часа"], token: token).status, 422)

        let created = call("POST", "v1/orders/\(order.id)/claims", body: body, token: token)
        XCTAssertEqual(created.status, 201)
        let claim = try decode(OrderClaim.self, created)
        XCTAssertEqual(claim.status, .submitted)
        XCTAssertEqual(claim.category, .late)
        XCTAssertEqual(claim.contactPreference, .messenger)
        XCTAssertNil(claim.chatUrl)

        clock.advance(21)
        let listed = try decode([OrderClaim].self, call("GET", "v1/orders/\(order.id)/claims", token: token))
        XCTAssertEqual(listed.first?.status, .accepted)
        XCTAssertEqual(listed.first?.chatUrl, "https://vyzovchat.ru")
        XCTAssertNotNil(listed.first?.managerComment)
        XCTAssertEqual(try self.order(order.id, token).claims?.count, 1)

        XCTAssertEqual(call("POST", "v1/orders/\(order.id)/claims", body: body, token: token).status, 201)
        XCTAssertEqual(call("POST", "v1/orders/\(order.id)/claims", body: body, token: token).status, 201)
        let limit = call("POST", "v1/orders/\(order.id)/claims", body: body, token: token)
        XCTAssertEqual(limit.status, 409)
        XCTAssertEqual(errorCode(limit), "claim_limit")

        clock.advance(14 * 86_400 + 200)
        let late = try self.order(order.id, token)
        XCTAssertEqual(late.status, .completed)
        XCTAssertEqual(late.canClaim, false, "через 14 дней после завершения претензию не оставить")
    }

    func testOldStateFileWithoutFeedbackDecodes() throws {
        let legacy = Data(#"{"users":[],"sessions":[],"carts":{},"favorites":{},"orders":[],"nextUserId":3,"nextOrderId":5}"#.utf8)
        let state = try JSONCoding.makeDecoder().decode(DemoState.self, from: legacy)
        XCTAssertEqual(state.nextOrderId, 5)
        XCTAssertTrue(state.claims.isEmpty)
        XCTAssertEqual(state.nextClaimId, 1)
    }
}
