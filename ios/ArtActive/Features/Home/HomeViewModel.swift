import Foundation
import Observation

/// Куда ведёт плитка главной.
enum HomeTarget: Equatable {
    case category(id: Int, title: String?)
    case siteLink(URL)
    case web(URL)
    case none
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var state: ViewState<[HomeSection]> = .loading

    @ObservationIgnored private let catalog: CatalogRepository

    init(catalog: CatalogRepository) {
        self.catalog = catalog
    }

    func load() async {
        if state.content == nil { state = .loading }
        do {
            let home = try await catalog.home()
            let sections = (home.sections ?? []).filter { $0.type != .unknown }
            state = sections.isEmpty ? .empty : .content(sections)
        } catch {
            guard !error.isCancellation else { return }
            if state.content == nil { state = .error(error.userMessage) }
        }
    }

    func target(for item: HomeItem) -> HomeTarget {
        if let id = item.categoryId { return .category(id: id, title: item.title) }
        guard let url = item.url?.resolvedURL else { return .none }
        if let host = url.host?.lowercased(), AppConfig.siteHosts.contains(host) { return .siteLink(url) }
        return .web(url)
    }
}
