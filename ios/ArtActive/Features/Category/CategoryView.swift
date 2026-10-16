import SwiftUI

/// Раздел: крошки, видео-шапка с параллаксом, чипсы подразделов, сортировка/фильтр,
/// сетка 2 колонки, сценарии, бесконечная подгрузка, pull-to-refresh.
struct CategoryView: View {
    @State private var viewModel: CategoryViewModel
    @State private var isFilterPresented = false
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: CategoryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                controls
                productsSection
            }
            .padding(.bottom, 32)
        }
        .background(Palette.catalogPage)
        .navigationTitle(Text(viewModel.title))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }
        }
        .refreshable {
            await Haptics.play(.refresh)
            await viewModel.load()
        }
        .sheet(isPresented: $isFilterPresented) {
            FilterSheet(query: viewModel.query, facets: viewModel.facets) { query in
                Task { await viewModel.apply(query) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { if viewModel.page.content == nil { await viewModel.load() } }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        switch viewModel.page {
        case .loading:
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 160, height: 14)
                SkeletonBlock(height: 180, radius: Radius.card)
            }
            .padding(.horizontal, Spacing.gutter)
            .shimmering()
        case let .content(page):
            VStack(alignment: .leading, spacing: 14) {
                if !page.breadcrumbs.isEmpty {
                    Breadcrumbs(crumbs: page.breadcrumbs) { crumb in
                        guard crumb.id != viewModel.categoryId else { return }
                        router.push(.category(id: crumb.id, title: crumb.name))
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
                if let video = page.heroVideo?.resolvedURL {
                    HeroVideo(url: video, image: page.category.image, reduceMotion: reduceMotion)
                        .padding(.horizontal, Spacing.gutter)
                }
                if !page.children.isEmpty {
                    ChipTabs(items: page.children, title: \.name, selected: nil) { node in
                        switch CatalogNavigation.route(for: node, preferChildren: false) {
                        case let .route(route): router.push(route)
                        case let .web(url): router.openWeb(url)
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
            }
        case .error, .empty:
            EmptyView()
        }
    }

    // MARK: - Sort / filter

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.play(.selection)
                isFilterPresented = true
            } label: {
                Label {
                    Text("Фильтры")
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
                .font(.aaChip)
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .brandGlass(in: Capsule(), interactive: true)
                .overlay(alignment: .topTrailing) {
                    if viewModel.query.activeFilterCount > 0 {
                        CounterBadge(count: viewModel.query.activeFilterCount).offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(PressableStyle())

            Text(viewModel.query.sort.title)
                .font(.aaCaption)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            if let total = viewModel.total {
                Text("\(total) товаров")
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.horizontal, Spacing.gutter)
    }

    private var sortMenu: some View {
        Menu {
            Picker(selection: Binding(
                get: { viewModel.query.sort },
                set: { newSort in
                    Haptics.play(.selection)
                    var query = viewModel.query
                    query.sort = newSort
                    Task { await viewModel.apply(query) }
                }
            )) {
                ForEach(ProductSort.allCases, id: \.self) { sort in
                    Text(sort.title).tag(sort)
                }
            } label: {
                Text("Сортировка")
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel(Text("Сортировка"))
    }

    // MARK: - Products

    @ViewBuilder
    private var productsSection: some View {
        let scenarios = viewModel.page.content?.scenarios ?? []
        if !scenarios.isEmpty {
            ScenarioRow(scenarios: scenarios) { router.openWeb($0) }
        }
        switch viewModel.productsState {
        case .loading:
            ProductGridSkeleton().padding(.horizontal, Spacing.gutter)
        case let .error(message):
            ErrorStateView(message: message) { await viewModel.reloadProducts() }
        case .empty:
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: String(localized: "Ничего не нашлось"),
                message: viewModel.query.activeFilterCount > 0 ? String(localized: "Попробуйте изменить фильтры") : nil,
                actionTitle: viewModel.query.activeFilterCount > 0 ? String(localized: "Сбросить фильтры") : nil
            ) {
                var query = viewModel.query
                query.priceMin = nil
                query.priceMax = nil
                query.colors = []
                Task { await viewModel.apply(query) }
            }
        case .content:
            VStack(spacing: 0) {
                ProductGridView(products: viewModel.products) { viewModel.loadMoreIfNeeded() }
                    .padding(.horizontal, Spacing.gutter)
                LoadMoreFooter(isLoading: viewModel.isLoadingMore, error: viewModel.loadMoreError) {
                    viewModel.retryLoadMore()
                }
            }
        }
        if let seo = viewModel.page.content?.seoHtml, !seo.isEmpty {
            CardContainer {
                HTMLText(html: seo, font: .aaBodySmall, color: Palette.textSecondary, collapsedHeight: 120, fadeColor: Palette.surface)
            }
            .padding(.horizontal, Spacing.gutter)
        }
    }
}

/// Видео-шапка раздела с параллаксом; тап — со звуком на весь экран.
private struct HeroVideo: View {
    let url: URL
    let image: String?
    let reduceMotion: Bool
    @State private var isFullscreen = false

    var body: some View {
        Button {
            isFullscreen = true
        } label: {
            ZStack {
                MediaBackground(image: image, video: url.absoluteString, reduceMotion: reduceMotion)
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .brandGlass(in: Circle(), tint: .black.opacity(0.25))
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .visualEffect { content, proxy in
                let minY = proxy.frame(in: .scrollView).minY
                return content.offset(y: reduceMotion ? 0 : min(max(-minY * 0.15, -20), 20))
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text("Видео о разделе"))
        .fullScreenCover(isPresented: $isFullscreen) {
            VideoScreen(url: url)
        }
    }
}

/// Карточки-сценарии (лендинги) — открываются в Safari внутри приложения.
private struct ScenarioRow: View {
    let scenarios: [Scenario]
    let open: (URL) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(scenarios, id: \.url) { scenario in
                    Button {
                        if let url = scenario.url.resolvedURL { open(url) }
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            RemoteImage(url: scenario.image?.resolvedURL, maxPixel: 600)
                            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scenario.title)
                                    .font(BrandFont.golos(15, .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Text("Подробнее")
                                    .font(.aaCaption)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                            .padding(12)
                        }
                        .frame(width: 220, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Spacing.gutter)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

#if DEBUG
#Preview("Раздел") {
    NavigationStack {
        CategoryView(viewModel: CategoryViewModel(categoryId: 225, initialTitle: "Столы", catalog: PreviewRepositories.shared))
    }
    .previewEnvironment()
}
#endif
