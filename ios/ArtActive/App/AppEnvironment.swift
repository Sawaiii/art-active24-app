import Foundation
import Observation

/// Контейнер зависимостей (DI через конструкторы). Создаётся один раз в `ArtActiveApp`.
@MainActor
@Observable
final class AppEnvironment {
    let catalog: CatalogRepository
    let venues: VenueRepository
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

    init(
        catalog: CatalogRepository,
        venues: VenueRepository,
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
        let client = APIClient(sessionManager: sessionManager)
        return AppEnvironment(
            catalog: LiveCatalogRepository(client: client),
            venues: LiveVenueRepository(client: client),
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
