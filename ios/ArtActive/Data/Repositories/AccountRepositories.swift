import Foundation

// MARK: - Cart

protocol CartRepository: Sendable {
    /// Серверный пересчёт (гость и авторизованный).
    func quote(_ items: [CartItemInput]) async throws -> Quote
    /// Серверная корзина пользователя.
    func serverCart() async throws -> Quote
    /// Заменить серверную корзину целиком.
    func replaceServerCart(_ items: [CartItemInput]) async throws -> Quote
}

struct LiveCartRepository: CartRepository {
    let client: APIClient

    func quote(_ items: [CartItemInput]) async throws -> Quote {
        try await client.request(try .send(.post, "/v1/cart/quote", body: CartItemsRequest(items: items), auth: .optional))
    }

    func serverCart() async throws -> Quote {
        try await client.request(.get("/v1/cart", auth: .required))
    }

    func replaceServerCart(_ items: [CartItemInput]) async throws -> Quote {
        try await client.request(try .send(.put, "/v1/cart", body: CartItemsRequest(items: items), auth: .required))
    }
}

// MARK: - Auth

protocol AuthRepository: Sendable {
    func requestCode(phone: String) async throws -> CodeResponse
    func verify(phone: String, code: String) async throws -> AuthSession
    func logout() async throws
}

struct LiveAuthRepository: AuthRepository {
    let client: APIClient

    func requestCode(phone: String) async throws -> CodeResponse {
        try await client.request(try .send(.post, "/v1/auth/code", body: CodeRequest(phone: phone)))
    }

    func verify(phone: String, code: String) async throws -> AuthSession {
        try await client.request(try .send(.post, "/v1/auth/verify", body: VerifyRequest(phone: phone, code: code)))
    }

    func logout() async throws {
        try await client.send(Endpoint(method: .post, path: "/v1/auth/logout", auth: .required))
    }
}

// MARK: - Profile

protocol ProfileRepository: Sendable {
    func me() async throws -> User
    func update(_ patch: ProfilePatch) async throws -> User
    func favorites() async throws -> [ProductSummary]
    func setFavorites(_ ids: [Int]) async throws -> [ProductSummary]
    func registerDevice(token: String) async throws
    /// Снять push-токен (до /v1/auth/logout).
    func unregisterDevice(token: String) async throws
    func info() async throws -> InfoPayload
    /// Скидка постоянного клиента: уровень, прогресс, лестница уровней.
    func loyalty() async throws -> Loyalty
}

struct LiveProfileRepository: ProfileRepository {
    let client: APIClient

    func me() async throws -> User {
        try await client.request(.get("/v1/me", auth: .required))
    }

    func update(_ patch: ProfilePatch) async throws -> User {
        try await client.request(try .send(.patch, "/v1/me", body: patch, auth: .required))
    }

    func favorites() async throws -> [ProductSummary] {
        let payload: ProductListPayload = try await client.request(.get("/v1/me/favorites", auth: .required))
        return payload.items ?? []
    }

    func setFavorites(_ ids: [Int]) async throws -> [ProductSummary] {
        let payload: ProductListPayload = try await client.request(
            try .send(.put, "/v1/me/favorites", body: FavoritesRequest(productIds: Array(ids.prefix(500))), auth: .required)
        )
        return payload.items ?? []
    }

    func registerDevice(token: String) async throws {
        try await client.send(try .send(.post, "/v1/me/devices", body: DeviceRequest(platform: "ios", token: token), auth: .required))
    }

    func unregisterDevice(token: String) async throws {
        try await client.send(try .send(.delete, "/v1/me/devices", body: DeviceTokenRequest(token: token), auth: .required))
    }

    func info() async throws -> InfoPayload {
        try await client.request(.get("/v1/info", cacheable: true))
    }

    func loyalty() async throws -> Loyalty {
        try await client.request(.get("/v1/me/loyalty", auth: .required))
    }
}

// MARK: - Orders

protocol OrderRepository: Sendable {
    func orders(page: Int) async throws -> Page<Order>
    func order(id: Int) async throws -> Order
    func checkout(_ request: CheckoutRequest, idempotencyKey: String) async throws -> Order
    func cancel(id: Int) async throws -> Order
    func createRequest(_ request: RequestCreate, idempotencyKey: String) async throws -> Order
    /// Состав заказа по разделам (КП / менеджер / позиции корзины).
    func composition(orderId: Int) async throws -> OrderComposition
    /// Где машина (только пока заказ «В пути»; иначе 409 tracking_unavailable).
    func vehicle(orderId: Int) async throws -> VehicleLocation
    /// Создать или изменить отзыв (после «Завершён», правка — 7 дней).
    func submitReview(orderId: Int, _ input: ReviewInput) async throws -> OrderReview
    func claims(orderId: Int) async throws -> [OrderClaim]
    func submitClaim(orderId: Int, _ input: ClaimInput) async throws -> OrderClaim
    func documents(orderId: Int) async throws -> [OrderDocument]
}

struct LiveOrderRepository: OrderRepository {
    let client: APIClient
    var pageSize = AppConfig.pageSize

    func orders(page: Int) async throws -> Page<Order> {
        let query = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(pageSize))]
        let result = try await client.requestWithMeta(.get("/v1/orders", query: query, auth: .required), as: [Order].self)
        return .make(items: result.value, meta: result.meta, page: page, limit: pageSize)
    }

    func order(id: Int) async throws -> Order {
        try await client.request(.get("/v1/orders/\(id)", auth: .required))
    }

    func checkout(_ request: CheckoutRequest, idempotencyKey: String) async throws -> Order {
        try await client.request(
            try .send(.post, "/v1/orders", body: request, auth: .required, headers: ["Idempotency-Key": idempotencyKey])
        )
    }

    func cancel(id: Int) async throws -> Order {
        try await client.request(Endpoint(method: .post, path: "/v1/orders/\(id)/cancel", auth: .required))
    }

    func createRequest(_ request: RequestCreate, idempotencyKey: String) async throws -> Order {
        try await client.request(
            try .send(.post, "/v1/requests", body: request, auth: .required, headers: ["Idempotency-Key": idempotencyKey])
        )
    }

    func composition(orderId: Int) async throws -> OrderComposition {
        try await client.request(.get("/v1/orders/\(orderId)/composition", auth: .required))
    }

    func vehicle(orderId: Int) async throws -> VehicleLocation {
        try await client.request(.get("/v1/orders/\(orderId)/vehicle", auth: .required))
    }

    func submitReview(orderId: Int, _ input: ReviewInput) async throws -> OrderReview {
        try await client.request(try .send(.post, "/v1/orders/\(orderId)/review", body: input, auth: .required))
    }

    func claims(orderId: Int) async throws -> [OrderClaim] {
        try await client.request(.get("/v1/orders/\(orderId)/claims", auth: .required))
    }

    func submitClaim(orderId: Int, _ input: ClaimInput) async throws -> OrderClaim {
        try await client.request(try .send(.post, "/v1/orders/\(orderId)/claims", body: input, auth: .required))
    }

    func documents(orderId: Int) async throws -> [OrderDocument] {
        try await client.request(.get("/v1/orders/\(orderId)/documents", auth: .required))
    }
}
