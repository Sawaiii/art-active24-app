import Foundation
import Observation

/// Список кейсов: загружается целиком (≈150 плиток), рубрики фильтруют локально — без ожидания сети.
@MainActor
@Observable
final class CasesViewModel {
    private(set) var state: ViewState<Void> = .loading
    private(set) var title: String?
    private(set) var categories: [CaseCategory] = []
    private(set) var allItems: [CaseSummary] = []
    var selectedCategoryId: Int?

    @ObservationIgnored private let repository: ContentRepository

    init(categoryId: Int?, repository: ContentRepository) {
        selectedCategoryId = categoryId
        self.repository = repository
    }

    var items: [CaseSummary] {
        guard let selectedCategoryId else { return allItems }
        return allItems.filter { $0.categoryId == selectedCategoryId }
    }

    /// Чипы рубрик: nil — «Все кейсы».
    var chipIds: [Int?] {
        let ids: [Int?] = categories.map { $0.id }
        return [nil] + ids
    }

    func categoryName(_ id: Int?) -> String? {
        guard let id else { return nil }
        return categories.first { $0.id == id }?.name
    }

    func load() async {
        if allItems.isEmpty { state = .loading }
        do {
            let list = try await repository.cases(categoryId: nil)
            title = list.title
            categories = list.categories ?? []
            allItems = list.items ?? []
            if let selectedCategoryId, !categories.contains(where: { $0.id == selectedCategoryId }) {
                self.selectedCategoryId = nil
            }
            state = allItems.isEmpty ? .empty : .content(())
        } catch {
            guard !error.isCancellation else { return }
            if allItems.isEmpty { state = .error(error.userMessage) }
        }
    }
}

/// Карточка кейса. Нет кейса в API (404) — экран предлагает открыть страницу сайта.
@MainActor
@Observable
final class CaseDetailViewModel {
    private(set) var state: ViewState<CaseStudy> = .loading
    let slug: String
    let initialTitle: String?

    @ObservationIgnored private let repository: ContentRepository

    init(slug: String, initialTitle: String?, repository: ContentRepository) {
        self.slug = slug
        self.initialTitle = initialTitle
        self.repository = repository
    }

    /// Страница кейса на сайте — запасной путь, если данных нет.
    var siteURL: URL? {
        URL(string: "/cases/\(slug)/", relativeTo: AppConfig.siteURL)?.absoluteURL
    }

    func load() async {
        if state.content == nil { state = .loading }
        do {
            state = .content(try await repository.caseStudy(slug: slug))
        } catch {
            guard !error.isCancellation else { return }
            guard state.content == nil else { return }
            state = Self.isNotFound(error) ? .empty : .error(error.userMessage)
        }
    }

    private static func isNotFound(_ error: Error) -> Bool {
        switch error as? APIError {
        case let .server(status, _, _, _)?: return status == 404
        case .http(404)?: return true
        default: return false
        }
    }
}
