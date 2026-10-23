import Foundation
import Observation

/// Контейнер зависимостей (DI через конструкторы). Создаётся один раз в `ArtActiveApp`.
@MainActor
@Observable
final class AppEnvironment {
    let catalog: CatalogRepository
    let venues: VenueRepository
    let content: ContentRepository
    let router: Router
    let auth: AuthStore
    let cart: CartStore
    let favorites: FavoritesStore
    let recent: RecentlyViewedStore
    let searchHistory: SearchHistoryStore
    let orders: OrdersStore
    let info: InfoStore
    let network: NetworkMonitor
    let push: PushService
    let deepLinks: DeepLinkHandler
    private let client: APIClient?
    @ObservationIgnored private var demoPollingTask: Task<Void, Never>?

    init(
        catalog: CatalogRepository,
        venues: VenueRepository,
        content: ContentRepository,
        cartRepository: CartRepository,
        authRepository: AuthRepository,
        profileRepository: ProfileRepository,
        orderRepository: OrderRepository,
        sessionManager: SessionManager,
        store: LocalStore,
        client: APIClient?
    ) {
        self.catalog = catalog
        self.venues = venues
        self.content = content
        self.client = client
        let router = Router()
        self.router = router
        let auth = AuthStore(sessionManager: sessionManager, authRepository: authRepository, profileRepository: profileRepository, store: store)
        self.auth = auth
        cart = CartStore(repository: cartRepository, store: store, isLoggedIn: { auth.isLoggedIn })
        favorites = FavoritesStore(repository: profileRepository, store: store, isLoggedIn: { auth.isLoggedIn })
        recent = RecentlyViewedStore(store: store)
        searchHistory = SearchHistoryStore(store: store)
        orders = OrdersStore(repository: orderRepository, store: store)
        info = InfoStore(repository: profileRepository)
        network = NetworkMonitor()
        push = PushService(repository: profileRepository, isLoggedIn: { auth.isLoggedIn })
        deepLinks = DeepLinkHandler(catalog: catalog, router: router)
        wireHooks()
    }

    static func live() -> AppEnvironment {
        let sessionManager = SessionManager()
        let client: APIClient
        if AppConfig.isDemoMode, DemoBackend.shared != nil {
            // Демо: все запросы API обслуживает встроенный бэкенд (картинки по-прежнему с сайта).
            client = APIClient(baseURL: DemoBackend.baseURL, sessionManager: sessionManager, urlSession: DemoURLProtocol.makeSession())
        } else {
            client = APIClient(sessionManager: sessionManager)
        }
        return AppEnvironment(
            catalog: LiveCatalogRepository(client: client),
            venues: LiveVenueRepository(client: client),
            content: LiveContentRepository(client: client),
            cartRepository: LiveCartRepository(client: client),
            authRepository: LiveAuthRepository(client: client),
            profileRepository: LiveProfileRepository(client: client),
            orderRepository: LiveOrderRepository(client: client),
            sessionManager: sessionManager,
            store: LocalStore(),
            client: client
        )
    }

    /// Старт приложения: восстановить сессию, подтянуть справочники и цены корзины.
    func bootstrap() async {
        if let client {
            await client.setUnauthorizedHandler { [weak self] in
                await self?.auth.handleSessionLost()
            }
        }
        await auth.restore()
        async let infoLoad: Void = info.load()
        async let quoteLoad: Void = cart.refreshQuote()
        _ = await (infoLoad, quoteLoad)
        if auth.isLoggedIn {
            await orders.load()
            await favorites.refreshFromServer()
            await push.requestAuthorizationIfNeeded()
        }
        if isDemoMode { startDemoOrderPolling() }
    }

    // MARK: - Демо-режим

    var isDemoMode: Bool { AppConfig.isDemoMode && DemoBackend.shared != nil }

    /// В демо статусы заявок двигаются по времени — периодически подтягиваем «Мои заказы»,
    /// чтобы срабатывал бейдж изменений в профиле.
    private func startDemoOrderPolling() {
        guard demoPollingTask == nil else { return }
        demoPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self else { return }
                if self.auth.isLoggedIn, !self.orders.orders.isEmpty {
                    await self.orders.load()
                }
            }
        }
    }

    /// «Сбросить демо-данные»: выход, очистка встроенного бэкенда и локальных данных.
    func resetDemoData() async {
        guard isDemoMode else { return }
        if auth.isLoggedIn { await auth.signOut() }
        DemoBackend.shared?.reset()
        orders.reset()
        favorites.clearLocal()
        cart.handleSignOut(explicit: true)
        recent.clear()
        searchHistory.clear()
    }

    private func wireHooks() {
        auth.onSignIn { [weak self] in
            guard let self else { return }
            await self.cart.mergeAfterSignIn()
            await self.favorites.mergeAfterSignIn()
            await self.orders.load()
            await self.push.requestAuthorizationIfNeeded()
            await self.push.registerIfPossible()
        }
        auth.beforeSignOut { [weak self] in
            await self?.push.unregister()
        }
        auth.onSignOut { [weak self] explicit in
            guard let self else { return }
            self.orders.reset()
            self.cart.handleSignOut(explicit: explicit)
            if explicit { self.favorites.clearLocal() }
            self.push.handleSignOut()
        }
    }
}
