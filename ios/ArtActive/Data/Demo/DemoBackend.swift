import Foundation

/// Встроенный бэкенд демо-режима: весь контракт contract/openapi.yaml поверх набора DemoData,
/// поведение — порт PHP-API (api/src). Работает синхронно под одной блокировкой; сеть не нужна.
/// Наружу ходят только картинки и видео товаров (их грузит ImagePipeline/AVPlayer напрямую).
final class DemoBackend: @unchecked Sendable {
    static let baseURL = URL(string: "https://demo.artactive.invalid/")!
    /// Код из «SMS» в демо-режиме — для любого мобильного номера.
    static let demoCode = "424242"

    /// Общий экземпляр приложения (nil, если набора нет в бандле).
    static let shared: DemoBackend? = {
        guard let dataset = DemoDataset.bundled() else { return nil }
        return DemoBackend(dataset: dataset, store: .live, notifier: DemoLocalNotifier(), clock: { Date() })
    }()

    private static let codeLength = 6
    private static let resendSeconds = 60
    private static let accessTTL = 1800
    private static let moscow = TimeZone(identifier: "Europe/Moscow") ?? .current

    let dataset: DemoDataset
    private let catalog: DemoCatalog
    private let quotes: DemoQuoteService
    private let store: DemoStateStore
    private let notifier: DemoOrderNotifier?
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var state: DemoState

    init(dataset: DemoDataset, store: DemoStateStore, notifier: DemoOrderNotifier?, clock: @escaping @Sendable () -> Date) {
        self.dataset = dataset
        catalog = DemoCatalog(data: dataset)
        quotes = DemoQuoteService(data: dataset)
        self.store = store
        self.notifier = notifier
        self.clock = clock
        state = store.load()
    }

    /// «Сбросить демо-данные»: пользователи, сессии, корзины, избранное, заявки.
    func reset() {
        lock.lock()
        state = DemoState()
        store.remove()
        lock.unlock()
        notifier?.removeAll()
    }

    // MARK: - Запрос

    func handle(method: String, url: URL, headers: [String: String], body: Data?) -> DemoResponse {
        lock.lock()
        defer { lock.unlock() }
        let request = DemoRequest(method: method.uppercased(), url: url, headers: headers, body: body)
        do {
            return try route(request)
        } catch let error as DemoError {
            return DemoJSON.error(error)
        } catch {
            return DemoJSON.error(DemoError(status: 500, code: "internal_error", message: "Внутренняя ошибка демо-режима"))
        }
    }

    private func route(_ request: DemoRequest) throws -> DemoResponse {
        let parts = request.segments
        guard parts.first == "v1" else { throw DemoError.notFound() }
        let path = Array(parts.dropFirst())

        switch (request.method, path.count, path.first ?? "") {
        case ("GET", 1, "home"): return DemoJSON.ok(catalog.home())
        case ("GET", 1, "info"): return DemoJSON.ok(dataset.raw("info.json") ?? [String: Any]())
        case ("GET", 2, "catalog") where path[1] == "tree": return DemoJSON.ok(DemoJSON.object(catalog.tree()))
        case ("GET", 2, "categories"): return try categoryPage(path[1])
        case ("GET", 3, "categories") where path[2] == "products": return try categoryProducts(path[1], request)
        case ("GET", 2, "products"): return try product(path[1])
        case ("GET", 1, "resolve"): return try resolve(request)
        case ("GET", 1, "search"): return try search(request)
        case ("GET", 1, "sale"): return DemoJSON.ok(catalog.sale())
        case ("GET", 1, "cases"): return try cases(request)
        case ("GET", 2, "cases"): return try caseStudy(path[1])
        case ("GET", 1, "venues"): return venues(request)
        case ("GET", 2, "venues") where path[1] == "filters": return DemoJSON.ok(dataset.raw("venue-filters.json") ?? [String: Any]())
        case ("GET", 2, "venues"): return try venue(path[1])
        case ("POST", 2, "cart") where path[1] == "quote":
            return DemoJSON.ok(DemoJSON.object(quotes.quote(try quotes.items(from: request.json["items"]))))
        case ("GET", 1, "cart"): return try cartGet(request)
        case ("PUT", 1, "cart"): return try cartPut(request)
        case ("POST", 2, "auth"): return try auth(path[1], request)
        case (_, _, "me"): return try me(Array(path.dropFirst()), request)
        case ("GET", 1, "orders"): return try ordersList(request)
        case ("POST", 1, "orders"): return try checkout(request)
        case ("GET", 2, "orders"): return try orderShow(path[1], request)
        case ("POST", 3, "orders") where path[2] == "cancel": return try orderCancel(path[1], request)
        case ("POST", 1, "requests"): return try createRequest(request)
        default: throw DemoError.notFound()
        }
    }

    // MARK: - Каталог

    private func categoryPage(_ rawId: String) throws -> DemoResponse {
        guard let id = Self.id(rawId), let page = catalog.categoryPage(id) else { throw DemoError.notFound("Раздел") }
        return DemoJSON.ok(DemoJSON.object(page))
    }

    private func categoryProducts(_ rawId: String, _ request: DemoRequest) throws -> DemoResponse {
        guard let id = Self.id(rawId), catalog.categoryPage(id) != nil else { throw DemoError.notFound("Раздел") }
        let sort = request.query["sort"] ?? "popular"
        guard ["popular", "price_low", "price_high", "new"].contains(sort) else {
            throw DemoError.badRequest("invalid_sort", "Неизвестная сортировка")
        }
        let colors = (request.query["colors"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.count <= 40 }
        var query = DemoProductQuery(categoryId: id, sort: sort)
        query.priceMin = request.query["priceMin"].flatMap { Int($0) }.map { max($0, 0) }
        query.priceMax = request.query["priceMax"].flatMap { Int($0) }.map { max($0, 0) }
        query.colors = Array(colors.prefix(20))
        query.page = request.int("page", default: 1, range: 1...10_000)
        query.limit = request.int("limit", default: 24, range: 1...60)
        let result = catalog.listProducts(query)
        let payload = ProductListPayload(items: result.items, facets: result.facets)
        return DemoJSON.ok(DemoJSON.object(payload), meta: DemoJSON.pageMeta(total: result.total, page: query.page, limit: query.limit))
    }

    private func product(_ rawId: String) throws -> DemoResponse {
        guard let id = Self.id(rawId), let raw = dataset.productRaw(id) else { throw DemoError.notFound("Товар") }
        return DemoJSON.ok(raw)
    }

    private func resolve(_ request: DemoRequest) throws -> DemoResponse {
        let rawPath = request.query["path"] ?? ""
        let path = URLComponents(string: rawPath)?.path ?? rawPath
        let segments = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard !segments.isEmpty, segments.count <= 4 else { throw DemoError.notFound("Страница") }
        if segments == ["sale"] { return DemoJSON.ok(["type": "sale"]) }
        if segments == ["cases"] { return DemoJSON.ok(["type": "cases"]) }
        if segments[0] == "cases", segments.count == 2, catalog.caseStudy(slug: segments[1].lowercased()) != nil {
            let payload: [String: Any] = ["type": "case", "slug": segments[1].lowercased()]
            return DemoJSON.ok(payload)
        }
        if segments[0] == "arenda-ploshchadki", segments.count > 1, let venueId = catalog.venueId(slug: segments[1]) {
            let payload: [String: Any] = ["type": "venue", "id": venueId]
            return DemoJSON.ok(payload)
        }
        if let resolved = catalog.resolve(path: path) {
            return DemoJSON.ok(DemoJSON.object(resolved))
        }
        let web: [String: Any] = ["type": "web", "url": "https://www.art-active24.ru/" + segments.joined(separator: "/") + "/"]
        return DemoJSON.ok(web)
    }

    // MARK: - Кейсы

    private func cases(_ request: DemoRequest) throws -> DemoResponse {
        var categoryId: Int?
        if let raw = request.query["category"], !raw.isEmpty {
            guard raw.count <= 6, raw.allSatisfy(\.isASCII), let value = Int(raw), value >= 0 else {
                throw DemoError.validation(["category": "Неизвестная рубрика"])
            }
            categoryId = value
        }
        let list = catalog.cases(categoryId: categoryId)
        let total = (list["items"] as? [Any])?.count ?? 0
        return DemoJSON.ok(list, meta: ["total": total])
    }

    private func caseStudy(_ rawSlug: String) throws -> DemoResponse {
        guard let study = catalog.caseStudy(slug: rawSlug.lowercased()) else { throw DemoError.notFound("Кейс") }
        return DemoJSON.ok(study)
    }

    private func search(_ request: DemoRequest) throws -> DemoResponse {
        let q = (request.query["q"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...100).contains(q.count) else { throw DemoError.validation(["q": "Введите от 2 до 100 символов"]) }
        let page = request.int("page", default: 1, range: 1...1000)
        let limit = request.int("limit", default: 24, range: 1...60)
        let result = catalog.search(q, offset: (page - 1) * limit, limit: limit)
        let payload: [String: Any] = [
            "products": DemoJSON.object(result.products),
            "categories": DemoJSON.object(result.categories),
        ]
        return DemoJSON.ok(payload, meta: DemoJSON.pageMeta(total: result.total, page: page, limit: limit))
    }

    private func venues(_ request: DemoRequest) -> DemoResponse {
        var query = DemoVenueQuery()
        query.events = Self.ids(request.query["events"])
        query.types = Self.ids(request.query["types"])
        query.metro = Self.ids(request.query["metro"])
        query.props = Self.ids(request.query["props"])
        for key in ["price", "capacity", "area"] {
            let from = request.query[key + "From"].flatMap { Int($0) }
            let to = request.query[key + "To"].flatMap { Int($0) }
            if from != nil || to != nil { query.ranges[key] = (from, to) }
        }
        query.collection = request.query["collection"].flatMap { Int($0) }
        query.page = request.int("page", default: 1, range: 1...10_000)
        query.limit = request.int("limit", default: 24, range: 1...60)
        let result = catalog.venues(query)
        let payload: [String: Any] = ["items": DemoJSON.object(result.items), "counts": result.counts]
        return DemoJSON.ok(payload, meta: DemoJSON.pageMeta(total: result.total, page: query.page, limit: query.limit))
    }

    private func venue(_ rawId: String) throws -> DemoResponse {
        guard let id = Self.id(rawId), let raw = dataset.venueRaw(id) else { throw DemoError.notFound("Площадка") }
        return DemoJSON.ok(raw)
    }

    // MARK: - Корзина

    private func cartGet(_ request: DemoRequest) throws -> DemoResponse {
        let user = try authenticate(request)
        return DemoJSON.ok(DemoJSON.object(quotes.quote(state.carts[String(user.id)] ?? [])))
    }

    private func cartPut(_ request: DemoRequest) throws -> DemoResponse {
        let user = try authenticate(request)
        let items = quotes.merged(try quotes.items(from: request.json["items"]))
        state.carts[String(user.id)] = items
        persist()
        return DemoJSON.ok(DemoJSON.object(quotes.quote(items)))
    }

    // MARK: - Вход

    private func auth(_ action: String, _ request: DemoRequest) throws -> DemoResponse {
        switch action {
        case "code":
            _ = try Self.phone(request.json["phone"], field: "phone", mobileOnly: true)
            let payload = CodeResponse(resendIn: Self.resendSeconds, codeLength: Self.codeLength)
            return DemoJSON.ok(DemoJSON.object(payload))
        case "verify":
            let phone = try Self.phone(request.json["phone"], field: "phone", mobileOnly: true)
            let code = (request.json.demoString("code") ?? "").trimmingCharacters(in: .whitespaces)
            guard code.count == Self.codeLength, code.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                throw DemoError.validation(["code": "Введите код из SMS"])
            }
            guard code == Self.demoCode else { throw DemoError.validation(["code": "Неверный код"]) }
            let (user, isNew) = findOrCreateUser(phone: phone)
            let session = issueSession(userId: user.id)
            persist()
            let payload = AuthSession(accessToken: session.accessToken, refreshToken: session.refreshToken,
                                      expiresIn: Self.accessTTL, user: user.dto, isNew: isNew)
            return DemoJSON.ok(DemoJSON.object(payload))
        case "refresh":
            let token = request.json.demoString("refreshToken") ?? ""
            guard !token.isEmpty, let index = state.sessions.firstIndex(where: { $0.refreshToken == token }),
                  let user = state.users.first(where: { $0.id == state.sessions[index].userId }) else {
                throw DemoError.unauthorized("Сессия истекла, войдите снова")
            }
            state.sessions[index].accessToken = Self.token()
            state.sessions[index].refreshToken = Self.token()
            persist()
            let session = state.sessions[index]
            let payload = AuthSession(accessToken: session.accessToken, refreshToken: session.refreshToken,
                                      expiresIn: Self.accessTTL, user: user.dto, isNew: false)
            return DemoJSON.ok(DemoJSON.object(payload))
        case "logout":
            let token = try bearer(request)
            state.sessions.removeAll { $0.accessToken == token }
            persist()
            return DemoJSON.noContent()
        default:
            throw DemoError.notFound()
        }
    }

    private func findOrCreateUser(phone: String) -> (DemoUser, Bool) {
        if let user = state.users.first(where: { $0.phone == phone }) { return (user, false) }
        let user = DemoUser(id: state.nextUserId, phone: phone)
        state.nextUserId += 1
        state.users.append(user)
        return (user, true)
    }

    private func issueSession(userId: Int) -> DemoSession {
        let session = DemoSession(userId: userId, accessToken: Self.token(), refreshToken: Self.token())
        state.sessions.append(session)
        return session
    }

    private func bearer(_ request: DemoRequest) throws -> String {
        let header = request.header("authorization") ?? ""
        guard header.lowercased().hasPrefix("bearer ") else { throw DemoError.unauthorized() }
        return String(header.dropFirst(7)).trimmingCharacters(in: .whitespaces)
    }

    private func authenticate(_ request: DemoRequest) throws -> DemoUser {
        let token = try bearer(request)
        guard let session = state.sessions.first(where: { $0.accessToken == token }),
              let user = state.users.first(where: { $0.id == session.userId }) else {
            throw DemoError.unauthorized()
        }
        return user
    }

    // MARK: - Профиль

    private func me(_ path: [String], _ request: DemoRequest) throws -> DemoResponse {
        let user = try authenticate(request)
        switch (request.method, path.first ?? "") {
        case ("GET", ""):
            return DemoJSON.ok(DemoJSON.object(user.dto))
        case ("PATCH", ""):
            return DemoJSON.ok(DemoJSON.object(try updateUser(user, request.json)))
        case ("GET", "favorites"):
            return favoritesResponse(userId: user.id)
        case ("PUT", "favorites"):
            guard let raw = request.json["productIds"] as? [Any], raw.count <= 500 else {
                throw DemoError.validation(["productIds": "Ожидается список id товаров"])
            }
            let ids = raw.compactMap { ($0 as? NSNumber)?.intValue }
            guard ids.count == raw.count, ids.allSatisfy({ $0 > 0 }) else {
                throw DemoError.validation(["productIds": "Ожидается список id товаров"])
            }
            var unique: [Int] = []
            for id in ids where !unique.contains(id) { unique.append(id) }
            state.favorites[String(user.id)] = unique
            persist()
            return favoritesResponse(userId: user.id)
        case ("POST", "devices"), ("DELETE", "devices"):
            let token = request.json.demoString("token") ?? ""
            guard !token.isEmpty, token.utf8.count <= 512 else { throw DemoError.validation(["token": "Некорректный push-токен"]) }
            return DemoJSON.noContent()
        default:
            throw DemoError.notFound()
        }
    }

    private func favoritesResponse(userId: Int) -> DemoResponse {
        let summaries = catalog.summaries(state.favorites[String(userId)] ?? [])
        let payload: [String: Any] = ["items": DemoJSON.object(summaries), "facets": [String: Any]()]
        return DemoJSON.ok(payload)
    }

    private func updateUser(_ user: DemoUser, _ body: [String: Any]) throws -> User {
        var updated = user
        var errors: [String: String] = [:]
        for (key, limit) in [("name", 100), ("company", 150)] where body[key] != nil {
            guard let value = (body[key] as? String)?.trimmingCharacters(in: .whitespaces), value.count <= limit else {
                errors[key] = "Не больше \(limit) символов"
                continue
            }
            if key == "name" { updated.name = value.isEmpty ? nil : value } else { updated.company = value.isEmpty ? nil : value }
        }
        if body["email"] != nil {
            let email = ((body["email"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            if !email.isEmpty, email.count > 150 || !Validation.isEmail(email) {
                errors["email"] = "Некорректный e-mail"
            } else {
                updated.email = email.isEmpty ? nil : email
            }
        }
        if !errors.isEmpty { throw DemoError.validation(errors) }
        if let index = state.users.firstIndex(where: { $0.id == user.id }) { state.users[index] = updated }
        persist()
        return updated.dto
    }

    // MARK: - Заявки

    private func ordersList(_ request: DemoRequest) throws -> DemoResponse {
        let user = try authenticate(request)
        let page = request.int("page", default: 1, range: 1...1000)
        let limit = request.int("limit", default: 24, range: 1...60)
        let now = clock()
        let mine = state.orders.filter { $0.userId == user.id }.sorted { $0.id > $1.id }
        let slice = mine.dropFirst((page - 1) * limit).prefix(limit).map { DemoOrderTimeline.present($0, now: now) }
        return DemoJSON.ok(DemoJSON.object(Array(slice)), meta: DemoJSON.pageMeta(total: mine.count, page: page, limit: limit))
    }

    private func orderShow(_ rawId: String, _ request: DemoRequest) throws -> DemoResponse {
        let user = try authenticate(request)
        guard let id = Self.id(rawId), let order = state.orders.first(where: { $0.id == id && $0.userId == user.id }) else {
            throw DemoError.notFound("Заказ")
        }
        return DemoJSON.ok(DemoJSON.object(DemoOrderTimeline.present(order, now: clock())))
    }

    private func orderCancel(_ rawId: String, _ request: DemoRequest) throws -> DemoResponse {
        let user = try authenticate(request)
        guard let id = Self.id(rawId), let index = state.orders.firstIndex(where: { $0.id == id && $0.userId == user.id }) else {
            throw DemoError.notFound("Заказ")
        }
        let now = clock()
        guard DemoOrderTimeline.status(of: state.orders[index], now: now) == .processing else {
            throw DemoError(status: 409, code: "cannot_cancel", message: "Заявку уже взяли в работу — для отмены свяжитесь с менеджером")
        }
        state.orders[index].cancelledAt = now
        persist()
        notifier?.cancelStatusChanges(orderId: id)
        return DemoJSON.ok(DemoJSON.object(DemoOrderTimeline.present(state.orders[index], now: now)))
    }

    private func checkout(_ request: DemoRequest) throws -> DemoResponse {
        let user = try authenticate(request)
        let key = try idempotencyKey(request)
        if let previous = try existing(userId: user.id, key: key, kinds: [.cart]) { return previous }
        let body = request.json
        let items = try quotes.items(from: body["items"], allowEmpty: false)
        let (eventDate, eventDateTo) = try eventDates(body, required: true)
        let deliveryInfo = try delivery(body["delivery"])
        let contactInfo = try contact(user, body)
        let comment = try text(body["comment"], max: 2000, field: "comment")

        let quote = quotes.quote(items)
        if let first = quote.lines.first(where: { !$0.available }) {
            throw DemoError(status: 409, code: "cart_changed", message: "«\(first.productName)»: \(first.warning ?? "позиция недоступна"). Обновите корзину")
        }
        let lines = quote.lines.map { line in
            OrderLine(
                productId: line.input.productId, productName: line.productName, productSlug: line.productSlug,
                image: line.image, art: line.art, complectTitle: line.complectTitle, subTitle: line.subTitle,
                timeLabel: line.timeLabel, qty: line.input.qty, qtyUnit: line.qtyUnit, extras: line.extras,
                unitPrice: line.unitPrice, total: line.total, onRequest: line.onRequest, input: line.input
            )
        }
        let order = createOrder(
            userId: user.id, key: key, kind: .cart, eventDate: eventDate, eventDateTo: eventDateTo,
            delivery: deliveryInfo, contact: contactInfo, comment: comment, subject: nil,
            lines: lines, total: min(quote.total, Pricing.maxTotal), hasOnRequest: quote.hasOnRequest == true
        )
        state.carts[String(user.id)] = []
        persist()
        notifier?.scheduleStatusChanges(for: order)
        return DemoJSON.ok(DemoJSON.object(DemoOrderTimeline.present(order, now: clock())), status: 201)
    }

    private func createRequest(_ request: DemoRequest) throws -> DemoResponse {
        let user = try authenticate(request)
        let key = try idempotencyKey(request)
        if let previous = try existing(userId: user.id, key: key, kinds: [.product, .venue, .callback]) { return previous }
        let body = request.json
        let kindRaw = body.demoString("kind") ?? ""
        let kind: OrderKind
        let subject: String
        switch kindRaw {
        case "product":
            kind = .product
            subject = try productSubject(body)
        case "venue":
            kind = .venue
            guard let venueId = body.demoInt("venueId"), venueId > 0 else {
                throw DemoError.validation(["venueId": "Ожидается числовой id"])
            }
            guard let name = dataset.venueName(venueId) else { throw DemoError.validation(["venueId": "Площадка не найдена"]) }
            subject = "Площадка: \(name)"
        case "callback":
            kind = .callback
            subject = "Обратный звонок"
        default:
            throw DemoError.validation(["kind": "Неизвестный тип заявки"])
        }
        let (eventDate, _) = try eventDates(body, required: kind == .venue)
        let contactInfo = try contact(user, body)
        if body.demoHas("guests") {
            guard let guests = body.demoInt("guests"), (1...100_000).contains(guests) else {
                throw DemoError.validation(["guests": "Укажите количество гостей числом"])
            }
        }
        _ = try text(body["eventType"], max: 100, field: "eventType")
        let comment = try text(body["comment"], max: 2000, field: "comment")

        let order = createOrder(
            userId: user.id, key: key, kind: kind, eventDate: eventDate, eventDateTo: nil,
            delivery: nil, contact: contactInfo, comment: comment, subject: String(subject.prefix(300)),
            lines: [], total: 0, hasOnRequest: false
        )
        persist()
        notifier?.scheduleStatusChanges(for: order)
        return DemoJSON.ok(DemoJSON.object(DemoOrderTimeline.present(order, now: clock())), status: 201)
    }

    private func productSubject(_ body: [String: Any]) throws -> String {
        guard let productId = body.demoInt("productId"), productId > 0 else {
            throw DemoError.validation(["productId": "Ожидается числовой id"])
        }
        guard let product = dataset.product(productId) else { throw DemoError.validation(["productId": "Товар не найден"]) }
        guard body.demoHas("complectId") else { return product.name }
        guard let complectId = body.demoInt("complectId"), complectId > 0 else {
            throw DemoError.validation(["complectId": "Ожидается числовой id"])
        }
        guard let complect = product.complects.first(where: { $0.id == complectId }) else {
            throw DemoError.validation(["complectId": "Комплект не найден"])
        }
        return "\(product.name) — \(complect.title)"
    }

    // swiftlint:disable:next function_parameter_count
    private func createOrder(
        userId: Int, key: String, kind: OrderKind, eventDate: String?, eventDateTo: String?,
        delivery: OrderDelivery?, contact: (name: String?, phone: String), comment: String?, subject: String?,
        lines: [OrderLine], total: Int, hasOnRequest: Bool
    ) -> DemoOrder {
        let id = state.nextOrderId
        state.nextOrderId += 1
        let order = DemoOrder(
            id: id, userId: userId, number: String(format: "AA-%06d", id), kind: kind, idempotencyKey: key,
            createdAt: clock(), cancelledAt: nil, eventDate: eventDate, eventDateTo: eventDateTo, delivery: delivery,
            contactName: contact.name, contactPhone: contact.phone, comment: comment, subject: subject,
            lines: lines, total: total, hasOnRequest: hasOnRequest
        )
        state.orders.append(order)
        return order
    }

    /// Повтор с тем же Idempotency-Key возвращает ранее созданную заявку того же типа.
    private func existing(userId: Int, key: String, kinds: [OrderKind]) throws -> DemoResponse? {
        guard let found = state.orders.first(where: { $0.userId == userId && $0.idempotencyKey == key }) else { return nil }
        guard kinds.contains(found.kind) else {
            throw DemoError(status: 422, code: "idempotency_key_reused", message: "Ключ Idempotency-Key уже использован для другой заявки")
        }
        return DemoJSON.ok(DemoJSON.object(DemoOrderTimeline.present(found, now: clock())), status: 201)
    }

    private func idempotencyKey(_ request: DemoRequest) throws -> String {
        let key = request.header("idempotency-key") ?? ""
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard (8...64).contains(key.count), key.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else {
            throw DemoError.badRequest("idempotency_key_required", "Нужен заголовок Idempotency-Key (8–64 символа)")
        }
        return key
    }

    /// Дата мероприятия не в прошлом (по Москве), окончание не раньше начала.
    private func eventDates(_ body: [String: Any], required: Bool) throws -> (String?, String?) {
        let from = try date(body["eventDate"], field: "eventDate")
        let to = try date(body["eventDateTo"], field: "eventDateTo")
        guard let from else {
            if required { throw DemoError.validation(["eventDate": "Укажите дату мероприятия"]) }
            return (nil, nil)
        }
        if from < today() { throw DemoError.validation(["eventDate": "Дата мероприятия уже прошла"]) }
        if let to, to < from { throw DemoError.validation(["eventDateTo": "Дата окончания раньше даты начала"]) }
        return (from, to == from ? nil : to)
    }

    private func today() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.moscow
        let parts = calendar.dateComponents([.year, .month, .day], from: clock())
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    private func date(_ value: Any?, field: String) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let raw = value as? String else { throw DemoError.validation([field: "Дата в формате ГГГГ-ММ-ДД"]) }
        if raw.isEmpty { return nil }
        guard let parsed = DayDate.date(from: raw), raw.count == 10, DayDate.string(from: parsed) == raw else {
            throw DemoError.validation([field: "Дата в формате ГГГГ-ММ-ДД"])
        }
        return raw
    }

    private func delivery(_ value: Any?) throws -> OrderDelivery {
        let raw = value as? [String: Any] ?? [:]
        switch raw.demoString("method") ?? "" {
        case "pickup":
            return OrderDelivery(method: .pickup, address: nil)
        case "delivery":
            let address = try text(raw["address"], max: 300, field: "delivery.address")
            guard let address, address.count >= 5 else {
                throw DemoError.validation(["delivery.address": "Укажите адрес доставки"])
            }
            return OrderDelivery(method: .delivery, address: address)
        default:
            throw DemoError.validation(["delivery.method": "Выберите доставку или самовывоз"])
        }
    }

    private func contact(_ user: DemoUser, _ body: [String: Any]) throws -> (name: String?, phone: String) {
        let phoneRaw = body.demoString("contactPhone") ?? ""
        let phone = phoneRaw.isEmpty ? user.phone : try Self.phone(phoneRaw, field: "contactPhone", mobileOnly: false)
        let name = try text(body["contactName"], max: 100, field: "contactName") ?? user.name
        return (name, phone)
    }

    private func text(_ value: Any?, max: Int, field: String) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let raw = value as? String else { throw DemoError.validation([field: "Ожидается текст"]) }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > max { throw DemoError.validation([field: "Не больше \(max) символов"]) }
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Помощники

    private func persist() {
        store.save(state)
    }

    private static func id(_ raw: String) -> Int? {
        guard (1...10).contains(raw.count), raw.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(raw)
    }

    private static func ids(_ csv: String?) -> [Int] {
        var out: [Int] = []
        for part in (csv ?? "").split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard (1...9).contains(trimmed.count), let value = Int(trimmed), !out.contains(value) else { continue }
            out.append(value)
        }
        return Array(out.prefix(100))
    }

    /// Российский номер +7XXXXXXXXXX (PhoneNumber.php): вход — только мобильный.
    static func phone(_ raw: Any?, field: String, mobileOnly: Bool) throws -> String {
        var digits = ((raw as? String) ?? "").filter { $0.isASCII && $0.isNumber }
        if digits.count == 10 {
            digits = "7" + digits
        } else if digits.count == 11, digits.first == "8" {
            digits = "7" + digits.dropFirst()
        }
        let chars = Array(digits)
        let valid = chars.count == 11 && chars[0] == "7" && (mobileOnly ? chars[1] == "9" : (chars[1] >= "3" && chars[1] <= "9"))
        guard valid else {
            let hint = mobileOnly ? "мобильный номер" : "номер"
            throw DemoError.validation([field: "Введите \(hint) в формате +7 (999) 999-99-99"])
        }
        return "+" + digits
    }

    private static func token() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
}

/// Разобранный запрос к демо-бэкенду.
struct DemoRequest {
    let method: String
    let url: URL
    let headers: [String: String]
    let body: Data?

    init(method: String, url: URL, headers: [String: String], body: Data?) {
        self.method = method
        self.url = url
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.body = body
    }

    /// Путь относительно базового адреса демо: ["v1", "catalog", "tree"].
    var segments: [String] {
        let basePath = DemoBackend.baseURL.path.split(separator: "/").map(String.init)
        let all = url.path.split(separator: "/").map(String.init)
        return Array(all.dropFirst(all.starts(with: basePath) ? basePath.count : 0))
    }

    var query: [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var out: [String: String] = [:]
        for item in items where out[item.name] == nil {
            out[item.name] = item.value ?? ""
        }
        return out
    }

    var json: [String: Any] {
        guard let body, !body.isEmpty else { return [:] }
        return DemoJSON.parse(body) as? [String: Any] ?? [:]
    }

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    func int(_ name: String, default value: Int, range: ClosedRange<Int>) -> Int {
        guard let raw = query[name], let parsed = Int(raw) else { return value }
        return min(max(parsed, range.lowerBound), range.upperBound)
    }
}
