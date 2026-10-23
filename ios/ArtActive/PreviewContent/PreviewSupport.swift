#if DEBUG
import Foundation
import SwiftUI

/// Фикстуры для SwiftUI Previews (реалистичные JSON по контракту в PreviewContent/Fixtures).
enum PreviewFixtures {
    static let viktoriaId = 7138
    static let plovId = 469
    static let batutId = 10500
    static let masterclassId = 721

    static let productFiles: [Int: String] = [
        viktoriaId: "product-viktoria",
        plovId: "product-plov",
        batutId: "product-batut",
        masterclassId: "product-masterclass",
    ]

    struct Catalog: Decodable {
        let home: HomePayload
        let tree: [CategoryNode]
        let category: CategoryPage
        let products: ProductListPayload
        let venues: VenueListPayload
        let venueFilters: VenueFiltersPayload
        let info: InfoPayload
        let order: Order
    }

    static func load<T: Decodable>(_ type: T.Type, file: String) throws -> T {
        guard let url = Bundle.main.url(forResource: file, withExtension: "json")
            ?? Bundle.main.url(forResource: file, withExtension: "json", subdirectory: "Fixtures") else {
            throw APIError.http(status: 404)
        }
        return try JSONCoding.makeDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static var catalog: Catalog {
        get throws { try load(Catalog.self, file: "catalog") }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.makeDecoder().decode(T.self, from: Data(json.utf8))
    }

    static let saleJSON = """
    {"title":"Выгодные предложения","items":[
     {"title":"Скидка 20% на всю мебель","subtitle":"Заказывая кейтеринг, вы экономите на аренде мебели.","image":"https://www.art-active24.ru/images/upload/ochered-20-skidka-new-art-2026-1-1.jpg","badge":"Скидка"},
     {"title":"Бесплатная доставка!","subtitle":"При заказе с воскресенья по четверг от 35 000 рублей доставка газелью 15 м2 бесплатно.","image":"https://www.art-active24.ru/images/upload/mashina-1-1-art-2026.jpg","badge":"Бонус"}
    ]}
    """

    static let casesJSON = """
    {"title":"Кейсы","categories":[{"id":2,"name":"Кейтеринг","count":1},{"id":1,"name":"Мероприятия","count":1}],"items":[
     {"slug":"keytering-ng","title":"Новогодний кейтеринг","image":"https://www.art-active24.ru/images/upload/cases26/b720x405/keys-ng-keytering-10.webp","budget":"300 000 ₽","budgetAmount":300000,"guests":100,"categoryId":2},
     {"slug":"serpuhov","title":"Серпухов","image":"https://www.art-active24.ru/images/upload/cases26/b720x405/dsc06922.webp","budget":"по запросу","categoryId":1}
    ]}
    """

    static let caseJSON = """
    {"slug":"keytering-ng","title":"Новогодний кейтеринг","url":"https://www.art-active24.ru/cases/keytering-ng/",
     "budget":"300 000 ₽","budgetAmount":300000,"guests":100,"categoryId":2,"category":{"id":2,"name":"Кейтеринг"},
     "media":[{"type":"image","url":"https://www.art-active24.ru/images/upload/keys-ng-keytering-10.jpg"},{"type":"image","url":"https://www.art-active24.ru/images/upload/keys-ng-keytering-9.jpg"}],
     "sections":[{"title":"Задача","html":"<p>Организовать новогоднее мероприятие с кейтерингом и фуршетом.</p>"},{"title":"Решение","html":"<p>Банкет, фуршет, квизы, фотозоны и мастер-классы.</p>"}],
     "links":[{"title":"Корнеры","image":"https://www.art-active24.ru/images/upload/yarm-domik-1_1.jpg","url":"https://www.art-active24.ru/arenda-yarmarochnyh-domikov/"}],
     "similar":[{"slug":"serpuhov","title":"Серпухов","image":"https://www.art-active24.ru/images/upload/cases26/b720x405/dsc06922.webp","budget":"по запросу","categoryId":1}]}
    """
}

/// Все репозитории на фикстурах: превью и ручная проверка вёрстки без API.
final class PreviewRepositories: CatalogRepository, VenueRepository, ContentRepository, CartRepository, AuthRepository,
    ProfileRepository, OrderRepository, @unchecked Sendable {
    static let shared = PreviewRepositories()

    private func delay() async { try? await Task.sleep(for: .milliseconds(250)) }

    // Catalog
    func home() async throws -> HomePayload { await delay(); return try PreviewFixtures.catalog.home }
    func tree() async throws -> [CategoryNode] { try PreviewFixtures.catalog.tree }
    func category(id: Int) async throws -> CategoryPage { try PreviewFixtures.catalog.category }

    func products(categoryId: Int, query: ProductQuery, page: Int) async throws -> ProductListPage {
        await delay()
        let payload = try PreviewFixtures.catalog.products
        let items = page == 1 ? payload.items ?? [] : []
        return ProductListPage(page: Page(items: items, page: page, total: items.count, hasMore: false), facets: payload.facets)
    }

    func product(id: Int) async throws -> Product {
        await delay()
        return try PreviewFixtures.load(Product.self, file: PreviewFixtures.productFiles[id] ?? "product-viktoria")
    }

    func search(_ text: String, page: Int) async throws -> SearchResult {
        let items = try PreviewFixtures.catalog.products.items ?? []
        let found = items.filter { $0.name.localizedCaseInsensitiveContains(text) }
        return SearchResult(products: Page(items: found, page: 1, total: found.count, hasMore: false), categories: [], correctedQuery: nil)
    }

    func resolve(path: String) async throws -> ResolvePayload {
        ResolvePayload(type: .product, id: PreviewFixtures.batutId, complectId: 5001, subId: "tramp-grunt-0", priceType: "rent", url: nil)
    }

    // Venues
    func venues(query: VenueQuery, page: Int) async throws -> VenueListPage {
        let payload = try PreviewFixtures.catalog.venues
        let items = page == 1 ? payload.items ?? [] : []
        return VenueListPage(page: Page(items: items, page: page, total: 728, hasMore: false), counts: payload.counts ?? [:])
    }

    func filters() async throws -> VenueFiltersPayload { try PreviewFixtures.catalog.venueFilters }
    func venue(id: Int) async throws -> Venue { try PreviewFixtures.load(Venue.self, file: "venue") }

    // Content: «Акции» и кейсы
    func sale() async throws -> SalePayload {
        await delay()
        return try PreviewFixtures.decode(SalePayload.self, PreviewFixtures.saleJSON)
    }

    func cases(categoryId: Int?) async throws -> CaseListPayload {
        await delay()
        let list = try PreviewFixtures.decode(CaseListPayload.self, PreviewFixtures.casesJSON)
        guard let categoryId else { return list }
        return CaseListPayload(title: list.title, categories: list.categories, items: list.items?.filter { $0.categoryId == categoryId })
    }

    func caseStudy(slug: String) async throws -> CaseStudy {
        await delay()
        var study = try PreviewFixtures.decode(CaseStudy.self, PreviewFixtures.caseJSON)
        if let products = try? PreviewFixtures.catalog.products.items {
            study = CaseStudy(
                slug: study.slug, title: study.title, url: study.url, description: study.description, image: study.image,
                budget: study.budget, budgetAmount: study.budgetAmount, guests: study.guests, categoryId: study.categoryId,
                category: study.category, media: study.media, sections: study.sections, products: Array(products.prefix(4)),
                links: study.links, similar: study.similar
            )
        }
        return study
    }

    // Cart: считаем той же формулой, что сервер
    func quote(_ items: [CartItemInput]) async throws -> Quote {
        var lines: [QuoteLine] = []
        for item in items {
            let product = try await self.product(id: item.productId)
            if item.isOptionLine {
                let price = try Pricing.optionLine(extras: product.extras, selected: item.extras ?? [], qty: item.qty)
                let names = (item.extras ?? []).compactMap { selection in product.extras.first { $0.id == selection.id }?.name }
                lines.append(QuoteLine(
                    key: "\(item.lineKey.hashValue)", input: item, productName: product.name, productSlug: product.slug,
                    image: product.summary.image, art: product.art, complectTitle: names.joined(separator: ", "),
                    subTitle: nil, priceLabel: nil, timeLabel: nil, qtyUnit: "шт", extras: nil,
                    unitPrice: price.unitPrice, total: price.total, onRequest: false, available: true, warning: nil
                ))
                continue
            }
            guard let complect = product.complects.first(where: { $0.id == item.complectId }) else { continue }
            let input = PricingInput(
                priceType: item.priceType ?? .rent,
                subId: item.subId,
                time: item.time,
                qty: item.qty,
                extras: item.extras ?? [],
                menu: item.menu ?? []
            )
            let price = try Pricing.calculate(complect: complect, extras: product.extras, input: input)
            let extras = (item.extras ?? []).compactMap { selection -> QuoteLineExtra? in
                guard let extra = product.extras.first(where: { $0.id == selection.id }) else { return nil }
                return QuoteLineExtra(name: extra.name, qty: selection.qty ?? 1, price: extra.price)
            }
            lines.append(QuoteLine(
                key: "\(item.lineKey.hashValue)",
                input: item,
                productName: product.name,
                productSlug: product.slug,
                image: product.summary.image,
                art: product.art,
                complectTitle: complect.title,
                subTitle: complect.subList.first { $0.id == item.subId }?.name,
                priceLabel: complect.side(item.priceType ?? .rent)?.label,
                timeLabel: price.timeLabel,
                qtyUnit: Configurator.unitWord(from: complect.side(item.priceType ?? .rent)?.postfix) ?? "шт",
                extras: extras,
                unitPrice: price.unitPrice,
                total: price.total,
                onRequest: price.onRequest,
                available: true,
                warning: nil
            ))
        }
        return Quote(lines: lines, total: lines.reduce(0) { $0 + $1.total }, hasOnRequest: lines.contains { $0.onRequest == true }, count: lines.count)
    }

    func serverCart() async throws -> Quote { Quote(lines: [], total: 0, hasOnRequest: false, count: 0) }
    func replaceServerCart(_ items: [CartItemInput]) async throws -> Quote { try await quote(items) }

    // Auth
    func requestCode(phone: String) async throws -> CodeResponse { CodeResponse(resendIn: 60, codeLength: 6) }

    func verify(phone: String, code: String) async throws -> AuthSession {
        AuthSession(accessToken: "preview", refreshToken: "preview", expiresIn: 900, user: Self.user, isNew: false)
    }

    func logout() async throws {}

    // Profile
    static let user = User(id: 1, phone: "+79991234567", name: "Иван", email: nil, company: nil, role: .customer)
    func me() async throws -> User { Self.user }
    func update(_ patch: ProfilePatch) async throws -> User { Self.user }
    func favorites() async throws -> [ProductSummary] { [] }
    func setFavorites(_ ids: [Int]) async throws -> [ProductSummary] { [] }
    func registerDevice(token: String) async throws {}
    func unregisterDevice(token: String) async throws {}
    func info() async throws -> InfoPayload { try PreviewFixtures.catalog.info }

    // Orders
    func orders(page: Int) async throws -> Page<Order> {
        let order = try PreviewFixtures.catalog.order
        return Page(items: page == 1 ? [order] : [], page: page, total: 1, hasMore: false)
    }

    func order(id: Int) async throws -> Order { try PreviewFixtures.catalog.order }
    func checkout(_ request: CheckoutRequest, idempotencyKey: String) async throws -> Order { try PreviewFixtures.catalog.order }
    func cancel(id: Int) async throws -> Order { try PreviewFixtures.catalog.order }
    func createRequest(_ request: RequestCreate, idempotencyKey: String) async throws -> Order { try PreviewFixtures.catalog.order }
}

extension AppEnvironment {
    static func preview() -> AppEnvironment {
        let repos = PreviewRepositories.shared
        let env = AppEnvironment(
            catalog: repos,
            venues: repos,
            content: repos,
            cartRepository: repos,
            authRepository: repos,
            profileRepository: repos,
            orderRepository: repos,
            sessionManager: SessionManager(keychain: KeychainStore(service: "ru.artactive24.app.preview")),
            store: LocalStore(folder: "preview-store"),
            client: nil
        )
        if env.cart.isEmpty {
            env.cart.add(CartItemInput(productId: PreviewFixtures.viktoriaId, complectId: 1724, priceType: .rent, time: TimeSelection(unit: .days, value: 2), qty: 2))
            env.cart.add(CartItemInput(productId: PreviewFixtures.plovId, complectId: 3101, subId: "1591", priceType: .rent, qty: 10, extras: [ExtraSelection(id: "povar")]))
        }
        return env
    }
}

extension View {
    /// Все окружения приложения для превью.
    @MainActor
    func previewEnvironment(_ env: AppEnvironment? = nil) -> some View {
        let env = env ?? AppEnvironment.preview()
        return self
            .environment(env)
            .environment(env.router)
            .environment(env.auth)
            .environment(env.cart)
            .environment(env.favorites)
            .environment(env.recent)
            .environment(env.orders)
            .environment(env.info)
            .tint(Palette.accent)
    }
}
#endif
