import SwiftUI

struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(RecentlyViewedStore.self) private var recent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    init(viewModel: HomeViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                logo
                content
            }
            .padding(.bottom, 24)
        }
        .background(Palette.catalogPage)
        .topScrollFade(Palette.catalogPage)
        .refreshable {
            Haptics.play(.refresh)
            await viewModel.load()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    env.router.push(.search)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(Text("Поиск"))
                .accessibilityIdentifier("home.search")
                ContactMenuButton {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                }
                .accessibilityLabel(Text("Связь с нами"))
            }
        }
        .task { if viewModel.state.content == nil { await viewModel.load() } }
    }

    /// Вордмарк «Арт-Актив · всё для мероприятий» как в шапке сайта (140×44).
    private var logo: some View {
        Image(colorScheme == .dark ? "LogoWhite" : "LogoDark")
            .resizable()
            .scaledToFit()
            .frame(width: 140, height: 44, alignment: .leading)
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, 8)
            .accessibilityLabel(Text("Арт-Актив"))
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            HomeSkeleton()
        case let .error(message):
            ErrorStateView(message: message) { await viewModel.load() }
                .padding(.top, 60)
        case .empty:
            EmptyStateView(
                systemImage: "sparkles",
                title: String(localized: "Скоро здесь будет витрина"),
                message: String(localized: "А пока загляните в каталог"),
                actionTitle: String(localized: "Перейти в каталог")
            ) { env.router.selectedTab = .catalog }
        case let .content(sections):
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    sectionView(section)
                }
                if !recent.items.isEmpty, !sections.contains(where: { $0.type == .recentlyViewed }) {
                    recentSection(title: nil)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        switch section.type {
        case .hero:
            if let item = section.items?.first {
                HeroBanner(item: item, reduceMotion: reduceMotion) { open(item) }
                    .padding(.horizontal, Spacing.gutter)
            }
        case .promoTiles:
            PromoTilesRow(items: section.items ?? []) { open($0) }
        case .directions:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: section.title ?? String(localized: "Наши возможности"))
                    .padding(.horizontal, Spacing.gutter)
                DirectionsGrid(items: section.items ?? [], reduceMotion: reduceMotion) { open($0) }
                    .padding(.horizontal, Spacing.gutter)
            }
        case .products:
            if let products = section.products, !products.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: section.title ?? String(localized: "Новинки"))
                        .padding(.horizontal, Spacing.gutter)
                    ProductRail(products: products)
                }
            }
        case .cases:
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: section.title ?? String(localized: "Наши кейсы"))
                    .padding(.horizontal, Spacing.gutter)
                CasesRow(items: section.items ?? []) { open($0) }
            }
        case .benefits:
            BenefitsList(title: section.title ?? String(localized: "Почему мы"), items: section.items ?? [])
                .padding(.horizontal, Spacing.gutter)
        case .recentlyViewed:
            if !recent.items.isEmpty {
                recentSection(title: section.title)
            }
        case .unknown:
            EmptyView()
        }
    }

    private func recentSection(title: String?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: title ?? String(localized: "Вы смотрели"),
                actionTitle: String(localized: "Очистить"),
                action: { withAnimation { recent.clear() } }
            )
            .padding(.horizontal, Spacing.gutter)
            ProductRail(products: recent.items)
        }
    }

    private func open(_ item: HomeItem) {
        Haptics.play(.selection)
        switch viewModel.target(for: item) {
        case let .category(id, title):
            env.router.push(.category(id: id, title: title))
        case let .siteLink(url):
            // Плитка без раздела (например, «Кулинарное казино») — страница сайта внутри приложения.
            env.router.openWeb(url)
        case let .web(url):
            env.router.openWeb(url)
        case .none:
            break
        }
    }
}

/// Лента товаров главной (снап по карточкам).
struct ProductRail: View {
    let products: [ProductSummary]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(products) { product in
                    ProductTile(product: product, width: 160)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, Spacing.gutter)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

// MARK: - Секции

private struct HeroBanner: View {
    let item: HomeItem
    let reduceMotion: Bool
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MediaBackground(image: item.image, video: item.video, reduceMotion: reduceMotion)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                if let title = item.title {
                    Text(title)
                        .font(BrandFont.golos(32, .semibold, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.aaBodySmall)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Button(action: action) {
                    Text("Подробнее")
                        .font(.aaButton)
                        .foregroundStyle(Palette.textProduct)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .brandGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(PressableStyle())
            }
            .padding(20)
        }
        .aspectRatio(0.82, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content.scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.96)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Фото или беззвучное зацикленное видео (при Reduce Motion — только фото).
struct MediaBackground: View {
    let image: String?
    let video: String?
    let reduceMotion: Bool

    /// Видео играет, только пока плитка на экране; при Reduce Motion — стоит на первом кадре.
    @State private var isOnScreen = false

    var body: some View {
        ZStack {
            if let imageURL = image?.resolvedURL {
                RemoteImage(url: imageURL, maxPixel: 1200)
            } else {
                Rectangle().fill(Palette.imagePlaceholder)
            }
            if let url = video?.resolvedURL {
                LoopingVideoView(url: url, isPlaying: isOnScreen && !reduceMotion)
                    .allowsHitTesting(false)
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }
}

private struct PromoTilesRow: View {
    let items: [HomeItem]
    let action: (HomeItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button { action(item) } label: {
                        ZStack(alignment: .bottomLeading) {
                            RemoteImage(url: item.image?.resolvedURL, maxPixel: 700)
                            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 6) {
                                if let badge = item.badge {
                                    BadgeView(text: badge, background: Palette.saleYellow, foreground: Palette.onYellow)
                                }
                                Text(item.title ?? "")
                                    .font(BrandFont.golos(17, .semibold, relativeTo: .headline))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                            }
                            .padding(14)
                        }
                        .frame(width: 260, height: 170)
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

private struct DirectionsGrid: View {
    let items: [HomeItem]
    let reduceMotion: Bool
    let action: (HomeItem) -> Void

    var body: some View {
        LazyVGrid(columns: ProductGrid.columns, spacing: Spacing.gridGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button { action(item) } label: {
                    ZStack(alignment: .bottomLeading) {
                        MediaBackground(image: item.image, video: item.video, reduceMotion: reduceMotion)
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                        Text(item.title ?? "")
                            .font(BrandFont.golos(15, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .padding(12)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

private struct CasesRow: View {
    let items: [HomeItem]
    let action: (HomeItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button { action(item) } label: {
                        ZStack(alignment: .bottomLeading) {
                            RemoteImage(url: item.image?.resolvedURL, maxPixel: 600)
                            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                            Text(item.title ?? "")
                                .font(BrandFont.golos(15, .semibold, relativeTo: .subheadline))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .padding(12)
                        }
                        .frame(width: 200, height: 200)
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

private struct BenefitsList: View {
    let title: String
    let items: [HomeItem]

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: title, font: .aaCartTitle)
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Palette.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title ?? "")
                                .font(.aaBlockTitle)
                                .foregroundStyle(Palette.textProduct)
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.aaBodySmall)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct HomeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.bgTertiary.opacity(0.7))
                .aspectRatio(0.82, contentMode: .fit)
            SkeletonBlock(width: 180, height: 22)
            ProductGridSkeleton(count: 4)
        }
        .padding(.horizontal, Spacing.gutter)
        .padding(.top, 8)
        .shimmering()
    }
}

#if DEBUG
#Preview("Главная") {
    NavigationStack {
        HomeView(viewModel: HomeViewModel(catalog: PreviewRepositories.shared))
    }
    .previewEnvironment()
}
#endif
