import Observation
import SwiftUI

@MainActor
@Observable
final class SearchViewModel {
    var text = ""
    private(set) var state: ViewState<SearchResult>?
    private(set) var products: [ProductSummary] = []
    private(set) var isLoadingMore = false

    let history: SearchHistoryStore
    @ObservationIgnored private let catalog: CatalogRepository
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var page = 1
    @ObservationIgnored private var hasMore = false

    static let minLength = 2

    init(catalog: CatalogRepository, history: SearchHistoryStore) {
        self.catalog = catalog
        self.history = history
    }

    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Вызывается при каждом изменении текста (дебаунс 300 мс).
    func textChanged() {
        searchTask?.cancel()
        guard trimmed.count >= Self.minLength else {
            state = nil
            products = []
            return
        }
        let query = trimmed
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.search(query)
        }
    }

    func submit() {
        history.add(trimmed)
        searchTask?.cancel()
        let query = trimmed
        guard query.count >= Self.minLength else { return }
        searchTask = Task { [weak self] in await self?.search(query) }
    }

    func use(_ query: String) {
        text = query
        history.add(query)
        textChanged()
    }

    private func search(_ query: String) async {
        if products.isEmpty { state = .loading }
        do {
            let result = try await catalog.search(String(query.prefix(100)), page: 1)
            guard !Task.isCancelled, query == trimmed else { return }
            products = result.products.items
            page = 1
            hasMore = result.products.hasMore
            state = result.products.items.isEmpty && result.categories.isEmpty ? .empty : .content(result)
        } catch {
            guard !error.isCancellation else { return }
            state = .error(error.userMessage)
        }
    }

    func loadMore() {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let query = trimmed
        Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingMore = false }
            guard let next = try? await self.catalog.search(query, page: self.page + 1), query == self.trimmed else { return }
            let known = Set(self.products.map(\.id))
            self.products += next.products.items.filter { !known.contains($0.id) }
            self.hasMore = next.products.hasMore
            self.page += 1
        }
    }
}

/// Поиск: системный .searchable, подсказки (история + популярные), результаты — разделы и товары.
struct SearchView: View {
    @State private var viewModel: SearchViewModel
    @Environment(Router.self) private var router

    init(viewModel: SearchViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, 32)
        }
        .background(Palette.catalogPage)
        .navigationTitle(Text("Поиск"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.text,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("Батут, стол, фотозона…")
        )
        .searchSuggestions {
            if viewModel.trimmed.isEmpty {
                ForEach(viewModel.history.queries, id: \.self) { query in
                    Label(query, systemImage: "clock.arrow.circlepath").searchCompletion(query)
                }
            }
        }
        .onChange(of: viewModel.text) { _, _ in viewModel.textChanged() }
        .onSubmit(of: .search) { viewModel.submit() }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .none:
            suggestions
        case .loading?:
            ProductGridSkeleton(count: 4).padding(.top, 12)
        case let .error(message)?:
            ErrorStateView(message: message) { viewModel.submit() }
        case .empty?:
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: String(localized: "Ничего не нашлось"),
                message: String(localized: "Проверьте написание или попробуйте другой запрос")
            )
        case let .content(result)?:
            results(result)
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !viewModel.history.queries.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(
                        title: String(localized: "Вы искали"),
                        font: .aaBlockTitle,
                        actionTitle: String(localized: "Очистить"),
                        action: { viewModel.history.clear() }
                    )
                    FlowLayout {
                        ForEach(viewModel.history.queries, id: \.self) { query in
                            ToggleChip(title: query, isOn: false, restingFill: Palette.surface) { viewModel.use(query) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: String(localized: "Популярное"), font: .aaBlockTitle)
                FlowLayout {
                    ForEach(SearchHistoryStore.popular, id: \.self) { query in
                        ToggleChip(title: query, isOn: false, restingFill: Palette.surface) { viewModel.use(query) }
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private func results(_ result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if let corrected = result.correctedQuery, !corrected.isEmpty, corrected != viewModel.trimmed {
                Text("Показаны результаты по запросу «\(corrected)»")
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            if !result.categories.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: String(localized: "Разделы"), font: .aaBlockTitle)
                    FlowLayout {
                        ForEach(result.categories) { node in
                            ToggleChip(title: node.name, isOn: false, restingFill: Palette.surface) {
                                switch CatalogNavigation.route(for: node, preferChildren: false) {
                                case let .route(route): router.push(route)
                                case let .web(url): router.openWeb(url)
                                }
                            }
                        }
                    }
                }
            }
            if !viewModel.products.isEmpty {
                SectionHeader(title: String(localized: "Товары"), font: .aaBlockTitle)
                ProductGridView(products: viewModel.products) { viewModel.loadMore() }
                LoadMoreFooter(isLoading: viewModel.isLoadingMore)
            }
        }
        .padding(.top, 12)
        .simultaneousGesture(TapGesture().onEnded { viewModel.history.add(viewModel.trimmed) })
    }
}

#if DEBUG
#Preview("Поиск") {
    NavigationStack {
        SearchView(viewModel: SearchViewModel(catalog: PreviewRepositories.shared, history: SearchHistoryStore(store: LocalStore(folder: "preview"))))
    }
    .previewEnvironment()
}
#endif
