import Foundation
import Observation

@MainActor
@Observable
final class CategoryViewModel {
    private(set) var page: ViewState<CategoryPage> = .loading
    private(set) var products: [ProductSummary] = []
    private(set) var productsState: ViewState<Void> = .loading
    private(set) var facets: ProductFacets?
    private(set) var total: Int?
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?
    private(set) var query = ProductQuery()

    let categoryId: Int
    let initialTitle: String?

    @ObservationIgnored private let catalog: CatalogRepository
    @ObservationIgnored private var currentPage = 1
    @ObservationIgnored private var hasMore = false
    @ObservationIgnored private var productsTask: Task<Void, Never>?

    init(categoryId: Int, initialTitle: String?, catalog: CatalogRepository) {
        self.categoryId = categoryId
        self.initialTitle = initialTitle
        self.catalog = catalog
    }

    var title: String {
        page.content?.displayTitle ?? initialTitle ?? ""
    }

    func load() async {
        async let pageLoad: Void = loadPage()
        async let productsLoad: Void = reloadProducts()
        _ = await (pageLoad, productsLoad)
    }

    private func loadPage() async {
        do {
            page = .content(try await catalog.category(id: categoryId))
        } catch {
            guard !error.isCancellation else { return }
            if page.content == nil { page = .error(error.userMessage) }
        }
    }

    func reloadProducts() async {
        productsTask?.cancel()
        if products.isEmpty { productsState = .loading }
        loadMoreError = nil
        do {
            let result = try await catalog.products(categoryId: categoryId, query: query, page: 1)
            products = result.page.items
            facets = result.facets ?? facets
            total = result.page.total
            hasMore = result.page.hasMore
            currentPage = 1
            productsState = products.isEmpty ? .empty : .content(())
        } catch {
            guard !error.isCancellation else { return }
            if products.isEmpty { productsState = .error(error.userMessage) }
        }
    }

    func loadMoreIfNeeded() {
        guard hasMore, !isLoadingMore, productsTask == nil else { return }
        isLoadingMore = true
        productsTask = Task { [weak self] in
            await self?.loadNextPage()
        }
    }

    func retryLoadMore() {
        loadMoreError = nil
        loadMoreIfNeeded()
    }

    private func loadNextPage() async {
        defer {
            isLoadingMore = false
            productsTask = nil
        }
        do {
            let result = try await catalog.products(categoryId: categoryId, query: query, page: currentPage + 1)
            let known = Set(products.map(\.id))
            products += result.page.items.filter { !known.contains($0.id) }
            hasMore = result.page.hasMore
            currentPage += 1
        } catch {
            guard !error.isCancellation else { return }
            loadMoreError = error.userMessage
        }
    }

    func apply(_ newQuery: ProductQuery) async {
        guard newQuery != query else { return }
        query = newQuery
        products = []
        await reloadProducts()
    }
}
