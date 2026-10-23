import SwiftUI

/// Корень: системный TabView (на iOS 26 — Liquid Glass таб-бар), стек на каждый таб,
/// глобальные шиты (Safari, вход), баннер «Нет сети».
struct RootView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router
        tabs
            .tint(Palette.accent)
            .overlay(alignment: .top) {
                if !env.network.isOnline {
                    OfflineBanner()
                        .padding(.top, 4)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: env.network.isOnline)
            .sheet(item: $router.webPage) { page in
                SafariView(url: page.url).ignoresSafeArea()
            }
            .sheet(isPresented: $router.isLoginPresented, onDismiss: {
                env.router.loginFinished(success: env.auth.isLoggedIn)
            }) {
                LoginView(viewModel: LoginViewModel(auth: env.auth))
            }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: env.router.tabSelection) {
                Tab("Главная", systemImage: "house", value: AppTab.home) { TabStack(tab: .home) }
                Tab("Каталог", systemImage: "square.grid.2x2", value: AppTab.catalog) { TabStack(tab: .catalog) }
                Tab("Корзина", systemImage: "cart", value: AppTab.cart) { TabStack(tab: .cart) }
                    .badge(env.cart.count)
                Tab("Избранное", systemImage: "heart", value: AppTab.favorites) { TabStack(tab: .favorites) }
                Tab("Профиль", systemImage: "person.crop.circle", value: AppTab.profile) { TabStack(tab: .profile) }
                    .badge(env.orders.unseenCount)
            }
        } else {
            TabView(selection: env.router.tabSelection) {
                TabStack(tab: .home)
                    .tabItem { Label("Главная", systemImage: "house") }
                    .tag(AppTab.home)
                TabStack(tab: .catalog)
                    .tabItem { Label("Каталог", systemImage: "square.grid.2x2") }
                    .tag(AppTab.catalog)
                TabStack(tab: .cart)
                    .tabItem { Label("Корзина", systemImage: "cart") }
                    .badge(env.cart.count)
                    .tag(AppTab.cart)
                TabStack(tab: .favorites)
                    .tabItem { Label("Избранное", systemImage: "heart") }
                    .tag(AppTab.favorites)
                TabStack(tab: .profile)
                    .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                    .badge(env.orders.unseenCount)
                    .tag(AppTab.profile)
            }
        }
    }
}

/// NavigationStack одного таба (свайп назад от края, large titles — системные).
struct TabStack: View {
    let tab: AppTab
    @Environment(AppEnvironment.self) private var env
    @Namespace private var zoomNamespace

    var body: some View {
        NavigationStack(path: env.router.path(for: tab)) {
            root
                .toolbar(.visible, for: .tabBar)
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                        .toolbar(route.hidesTabBar ? .hidden : .visible, for: .tabBar)
                }
        }
        .environment(\.zoomNamespace, zoomNamespace)
        // Контент не просвечивает под статус-баром и плавающими кнопками навбара.
        .softTopScrollEdge()
    }

    @ViewBuilder
    private var root: some View {
        switch tab {
        case .home:
            HomeView(viewModel: HomeViewModel(catalog: env.catalog))
        case .catalog:
            CatalogView(viewModel: CatalogViewModel(catalog: env.catalog))
        case .cart:
            CartView(viewModel: CartViewModel(cart: env.cart, favorites: env.favorites))
        case .favorites:
            FavoritesView()
        case .profile:
            ProfileView()
        }
    }
}

extension Route {
    /// Как на сайте: на карточках, оформлении и деталях нижнее меню скрыто.
    var hidesTabBar: Bool {
        switch self {
        case .product, .venue, .checkout, .order: return true
        default: return false
        }
    }
}

/// Фабрика экранов по маршруту.
struct RouteView: View {
    let route: Route
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch route {
        case let .catalogLevel(node):
            CatalogLevelView(node: node)
        case let .category(id, title):
            CategoryView(viewModel: CategoryViewModel(categoryId: id, initialTitle: title, catalog: env.catalog))
        case let .product(id, preselect):
            ProductScreen(viewModel: ProductViewModel(productId: id, preselect: preselect, catalog: env.catalog))
        case let .venues(collectionId, title):
            VenuesView(viewModel: VenuesViewModel(collectionId: collectionId, title: title, repository: env.venues))
        case let .venue(id):
            VenueDetailView(viewModel: VenueDetailViewModel(venueId: id, repository: env.venues))
        case .search:
            SearchView(viewModel: SearchViewModel(catalog: env.catalog, history: env.searchHistory))
        case .orders:
            OrdersView()
        case let .order(id):
            OrderDetailView(viewModel: OrderDetailViewModel(orderId: id, orders: env.orders))
        case .favorites:
            FavoritesView()
        case .profileEdit:
            ProfileEditView(viewModel: ProfileEditViewModel(auth: env.auth))
        case let .info(page):
            InfoPageView(page: page)
        case .checkout:
            CheckoutView(viewModel: CheckoutViewModel(cart: env.cart, orders: env.orders, auth: env.auth))
        }
    }
}
