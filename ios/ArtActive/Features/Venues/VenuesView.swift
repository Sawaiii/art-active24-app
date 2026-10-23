import SwiftUI

/// Агрегатор площадок: фасетные фильтры, пилюли применённых, карточки с каруселью фото.
struct VenuesView: View {
    @State private var viewModel: VenuesViewModel
    @State private var isFilterPresented = false
    @Environment(Router.self) private var router

    init(viewModel: VenuesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding(.bottom, 32)
        }
        .background(Palette.catalogPage)
        .navigationTitle(Text(viewModel.title ?? String(localized: "Площадки")))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            Haptics.play(.refresh)
            await viewModel.reload()
        }
        .sheet(isPresented: $isFilterPresented) {
            VenueFilterSheet(query: viewModel.query, filters: viewModel.filters, counts: viewModel.counts) { query in
                Task { await viewModel.apply(query) }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { if viewModel.venues.isEmpty { await viewModel.load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
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
                    .frame(minHeight: 44)
                    .brandGlass(in: Capsule(), interactive: true)
                    .overlay(alignment: .topTrailing) {
                        if viewModel.query.activeCount > 0 {
                            CounterBadge(count: viewModel.query.activeCount).offset(x: 6, y: -6)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("venues.filter")
                Spacer()
                if let total = viewModel.total {
                    Text("\(total) площадок")
                        .font(.aaCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            let chips = viewModel.appliedChips
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips) { chip in
                            Button {
                                Haptics.play(.selection)
                                Task { await viewModel.removeChip(chip.id) }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(chip.title)
                                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                                }
                                .font(.aaCaption)
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(Palette.accentTint10))
                                // Видимая пилюля компактная, зона нажатия — 44 pt.
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Убрать фильтр \(chip.title)"))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.gutter)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            VStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    VenueCardSkeleton()
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .shimmering()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Загрузка"))
        case let .error(message):
            ErrorStateView(message: message) { await viewModel.reload() }
        case .empty:
            EmptyStateView(
                systemImage: "building.2",
                title: String(localized: "Площадок не нашлось"),
                message: String(localized: "Попробуйте ослабить фильтры"),
                actionTitle: viewModel.query.activeCount > 0 ? String(localized: "Сбросить фильтры") : nil
            ) {
                Task { await viewModel.apply(viewModel.query.cleared()) }
            }
        case .content:
            ForEach(viewModel.venues) { venue in
                VenueCard(venue: venue) { router.push(.venue(id: venue.id)) }
                    .padding(.horizontal, Spacing.gutter)
                    .task {
                        if venue.id == viewModel.venues.last?.id { await viewModel.loadMore() }
                    }
            }
            LoadMoreFooter(isLoading: viewModel.isLoadingMore, error: viewModel.loadMoreError) {
                Task { await viewModel.loadMore() }
            }
        }
    }
}

/// Скелетон карточки площадки: фото 4:3, тип, название, адрес, цена — те же отступы, что у VenueCard.
private struct VenueCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.bgTertiary.opacity(0.7))
                .aspectRatio(MediaAspect.photo, contentMode: .fit)
            SkeletonBlock(width: 80, height: 12)
            SkeletonBlock(height: 18)
            SkeletonBlock(width: 200, height: 14)
            SkeletonBlock(width: 120, height: 16)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous).fill(Palette.surface))
    }
}

/// Карточка площадки: до 8 фото с точками, теги площадь/вместимость/до метро, название, адрес, метро, цена.
struct VenueCard: View {
    let venue: VenueSummary
    let action: () -> Void
    @State private var photoIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let photos = Array((venue.photos ?? []).prefix(8))
            ZStack(alignment: .bottom) {
                TabView(selection: $photoIndex) {
                    if photos.isEmpty {
                        RemoteImage(url: nil).tag(0)
                    } else {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, raw in
                            RemoteImage(url: raw.resolvedURL, maxPixel: 900).tag(index)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                if photos.count > 1 {
                    PageDots(count: photos.count, current: photoIndex, activeColor: .white, inactiveColor: .white.opacity(0.5))
                        .padding(.bottom, 10)
                }
            }
            // Фото площадок 600×450 — 4:3. Для VoiceOver тап по фото дублирует кнопку ниже.
            .accessibilityHidden(true)
            .aspectRatio(MediaAspect.photo, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(alignment: .topLeading) {
                VenueTags(area: venue.area, capacity: venue.capacity, metroDistance: venue.metro?.first?.distance)
                    .padding(10)
            }
            .zoomTransitionSource(id: ZoomID.venue(venue.id))
            .onTapGesture(perform: action)

            Button(action: action) {
                VStack(alignment: .leading, spacing: 6) {
                    if let type = venue.type {
                        Text(type).font(.aaCaption).foregroundStyle(Palette.textSecondary)
                    }
                    Text(venue.name)
                        .font(BrandFont.golos(17, .semibold))
                        .foregroundStyle(Palette.textProduct)
                        .multilineTextAlignment(.leading)
                    if let address = venue.address {
                        Text(address).font(.aaBodySmall).foregroundStyle(Palette.textSecondary)
                    }
                    if let metro = venue.metro, !metro.isEmpty {
                        MetroList(stations: metro)
                    }
                    PriceTagView(tag: venue.price)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("venue.card.\(venue.id)")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous).fill(Palette.surface))
        .accessibilityElement(children: .contain)
    }
}

struct VenueTags: View {
    let area: Int?
    let capacity: Int?
    let metroDistance: Int?

    var body: some View {
        // Узкая карточка («Похожие площадки») не вмещает три тега в строку — теги переносились
        // на две строки. Тогда убираем «до метро»: расстояние и так есть в строке станции ниже.
        ViewThatFits(in: .horizontal) {
            tags(includeMetro: true)
            tags(includeMetro: false)
        }
    }

    private func tags(includeMetro: Bool) -> some View {
        HStack(spacing: 6) {
            if let area { tag("\(area) м²", "square.dashed") }
            if let capacity { tag(String(localized: "до \(capacity) чел."), "person.2") }
            if includeMetro, let metroDistance { tag(String(localized: "\(metroDistance) м до метро"), "figure.walk") }
        }
    }

    private func tag(_ text: String, _ symbol: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .font(BrandFont.golos(11, .semibold, relativeTo: .caption2))
        .foregroundStyle(Palette.textProduct)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .brandGlass(in: Capsule())
    }
}

/// Станции метро с цветом линии.
struct MetroList: View {
    let stations: [MetroStation]

    var body: some View {
        FlowLayout(spacing: 10, lineSpacing: 6) {
            ForEach(Array(stations.enumerated()), id: \.offset) { _, station in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(hexString: station.color) ?? Palette.disabled)
                        .frame(width: 9, height: 9)
                    Text(station.name ?? "")
                        .font(.aaCaption)
                        .foregroundStyle(Palette.text)
                    if let distance = station.distance {
                        Text("\(distance) м")
                            .font(.aaCaption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#if DEBUG
#Preview("Площадки") {
    NavigationStack {
        VenuesView(viewModel: VenuesViewModel(collectionId: nil, title: nil, repository: PreviewRepositories.shared))
    }
    .previewEnvironment()
}
#endif
