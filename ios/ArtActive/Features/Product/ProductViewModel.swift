import Foundation
import Observation

@MainActor
@Observable
final class ProductViewModel {
    let productId: Int
    let preselect: ProductPreselection?
    private(set) var state: ViewState<Product> = .loading

    @ObservationIgnored private let catalog: CatalogRepository

    init(productId: Int, preselect: ProductPreselection?, catalog: CatalogRepository) {
        self.productId = productId
        self.preselect = preselect
        self.catalog = catalog
    }

    var product: Product? { state.content }

    func load(recent: RecentlyViewedStore) async {
        if state.content == nil { state = .loading }
        do {
            let product = try await catalog.product(id: productId)
            state = .content(product)
            recent.record(product.summary)
        } catch {
            guard !error.isCancellation else { return }
            if state.content == nil { state = .error(error.userMessage) }
        }
    }

    /// Какой экран рисовать для шаблона карточки.
    enum Layout {
        case configurator
        case simple
        case showcase
        case staff
        case program
    }

    static func layout(for product: Product) -> Layout {
        switch product.template {
        case .configurator:
            return product.complects.isEmpty ? .simple : .configurator
        case .simple, .unknown:
            return .simple
        case .showcase:
            return .showcase
        case .staff:
            return .staff
        case .program:
            return .program
        }
    }
}
