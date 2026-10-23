import SwiftUI

/// Карточка товара: загрузка и отдельный рендер на каждый шаблон сайта.
struct ProductScreen: View {
    @State private var viewModel: ProductViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(FavoritesStore.self) private var favorites
    @Environment(RecentlyViewedStore.self) private var recent

    init(viewModel: ProductViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProductSkeleton()
            case let .error(message):
                ErrorStateView(message: message) { await viewModel.load(recent: recent) }
                    .frame(maxHeight: .infinity)
            case .empty:
                EmptyStateView(systemImage: "shippingbox", title: String(localized: "Товар не найден"))
            case let .content(product):
                productBody(product)
            }
        }
        .background(Palette.page)
        .topScrollFade(Palette.page)
        .softTopScrollEdge()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let product = viewModel.product {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let url = product.shareURL {
                        ShareLink(item: url, subject: Text(product.name)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(Text("Поделиться"))
                    }
                    Button {
                        Haptics.play(.favorite)
                        favorites.toggle(product.summary)
                    } label: {
                        Image(systemName: favorites.contains(product.id) ? "heart.fill" : "heart")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(favorites.contains(product.id) ? Text("Убрать из избранного") : Text("В избранное"))
                }
            }
        }
        .zoomTransitionDestination(id: ZoomID.product(viewModel.productId))
        .task {
            if viewModel.product == nil { await viewModel.load(recent: recent) }
            // Избранное хранит снимок товара — обновляем аву и цену свежими данными карточки.
            if let product = viewModel.product { favorites.refresh(product.summary) }
        }
    }

    @ViewBuilder
    private func productBody(_ product: Product) -> some View {
        switch ProductViewModel.layout(for: product) {
        case .configurator:
            ConfiguratorProductView(
                viewModel: ConfiguratorViewModel(product: product, preselect: viewModel.preselect, cart: env.cart)
            )
        case .simple:
            SimpleProductView(product: product)
        case .showcase:
            ShowcaseProductView(product: product)
        case .staff:
            StaffProductView(product: product)
        case .program:
            ProgramProductView(product: product)
        }
    }
}

// MARK: - Общие секции карточки

/// Заголовок товара: название Inter 17/600 + «арт: 07138».
struct ProductTitleRow: View {
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let crumbs = product.breadcrumbs, !crumbs.isEmpty {
                ProductBreadcrumbs(crumbs: crumbs)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(product.name)
                    .font(BrandFont.inter(22, .semibold, relativeTo: .title2))
                    .tracking(-0.3)
                    .foregroundStyle(Palette.textProduct)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            if let art = product.art, !art.isEmpty {
                ArticleBadge(art: art)
            }
            if let lead = product.lead, !lead.isEmpty {
                Text(lead)
                    .font(.pBody)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }
}

struct ProductBreadcrumbs: View {
    let crumbs: [Crumb]
    @Environment(Router.self) private var router

    var body: some View {
        Breadcrumbs(crumbs: crumbs) { crumb in
            router.push(.category(id: crumb.id, title: crumb.name))
        }
    }
}

/// «Характеристики» — строки имя/значение с пунктиром.
struct SpecsSection: View {
    let specs: [Spec]
    var title: String = String(localized: "Характеристики")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.pH3)
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 10) {
                ForEach(Array(specs.enumerated()), id: \.offset) { _, spec in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(spec.name)
                            .font(.pBody)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: 12)
                        Text(spec.value)
                            .font(BrandFont.inter(15, .medium))
                            .foregroundStyle(Palette.textProduct)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                    Divider().overlay(Palette.hairline)
                }
            }
        }
    }
}

/// «Описание» — HTML, свёрнуто с «Показать ещё».
struct DescriptionSection: View {
    let html: String
    var title: String = String(localized: "Описание")

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.pH3)
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
            HTMLText(html: html, collapsedHeight: 140)
        }
    }
}

/// «Похожие товары».
struct SimilarSection: View {
    let title: String
    let products: [ProductSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.pSection)
                .tracking(-0.6)
                .foregroundStyle(Palette.textProduct)
                .padding(.horizontal, Spacing.gutterProduct)
                .accessibilityAddTraits(.isHeader)
            ProductRail(products: products)
        }
    }
}

/// Блок «Связаться с менеджером».
struct ManagerContactSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Остались вопросы?")
                .font(.pH3)
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
            Text("Менеджер ответит круглосуточно и поможет собрать комплект.")
                .font(.pBody)
                .foregroundStyle(Palette.textSecondary)
            ContactButtonsRow()
        }
    }
}

private struct ProductSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Palette.bgTertiary.opacity(0.6))
                    .aspectRatio(MediaAspect.photo, contentMode: .fit)
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonBlock(height: 22)
                    SkeletonBlock(width: 90, height: 16)
                    HStack(spacing: 10) {
                        SkeletonBlock(height: 56, radius: Radius.md)
                        SkeletonBlock(height: 56, radius: Radius.md)
                    }
                    SkeletonBlock(height: 40, radius: Radius.md)
                }
                .padding(.horizontal, Spacing.gutterProduct)
            }
            .shimmering()
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Загрузка"))
    }
}

#if DEBUG
#Preview("Стол Виктория 180") {
    NavigationStack {
        ProductScreen(viewModel: ProductViewModel(productId: PreviewFixtures.viktoriaId, preselect: nil, catalog: PreviewRepositories.shared))
    }
    .previewEnvironment()
}

#Preview("Плов") {
    NavigationStack {
        ProductScreen(viewModel: ProductViewModel(productId: PreviewFixtures.plovId, preselect: nil, catalog: PreviewRepositories.shared))
    }
    .previewEnvironment()
}

#Preview("Батут") {
    NavigationStack {
        ProductScreen(viewModel: ProductViewModel(productId: PreviewFixtures.batutId, preselect: nil, catalog: PreviewRepositories.shared))
    }
    .previewEnvironment()
}

#Preview("Мастер-класс") {
    NavigationStack {
        ProductScreen(viewModel: ProductViewModel(productId: PreviewFixtures.masterclassId, preselect: nil, catalog: PreviewRepositories.shared))
    }
    .previewEnvironment()
}
#endif
