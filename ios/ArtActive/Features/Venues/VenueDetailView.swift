import MapKit
import SwiftUI

/// Карточка площадки: галерея, тип, адрес, метро с цветом линии, параметры, карта с пином,
/// описание, «Как арендовать», форма «Заявка на расчёт», похожие площадки.
struct VenueDetailView: View {
    @State private var viewModel: VenueDetailViewModel
    @State private var request: RequestSubject?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(viewModel: VenueDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                VenueDetailSkeleton()
            case let .error(message):
                ErrorStateView(message: message) { await viewModel.load() }
            case .empty:
                EmptyStateView(systemImage: "building.2", title: String(localized: "Площадка не найдена"))
            case let .content(venue):
                content(venue)
            }
        }
        .background(Palette.page)
        .topScrollFade(Palette.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = viewModel.state.content?.shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel(Text("Поделиться"))
                }
            }
        }
        .zoomTransitionDestination(id: ZoomID.venue(viewModel.venueId))
        .sheet(item: $request) { subject in
            RequestFormSheet(viewModel: RequestFormViewModel(subject: subject, orders: env.orders))
        }
        .task { if viewModel.state.content == nil { await viewModel.load() } }
    }

    private func content(_ venue: Venue) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionLarge) {
                // Подложка видна, пока грузится фото: без неё шапка — пустой белый прямоугольник.
                GalleryPager(items: GalleryItem.from(urls: venue.photos ?? []), aspectRatio: MediaAspect.photo, imageBackground: Palette.imagePlaceholder)

                VStack(alignment: .leading, spacing: 10) {
                    if let type = venue.type {
                        Text(type).font(.aaCaption).foregroundStyle(Palette.accent)
                    }
                    Text(venue.name)
                        .font(.aaPageTitle)
                        .foregroundStyle(Palette.textProduct)
                        .accessibilityAddTraits(.isHeader)
                    if let address = venue.address {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.aaBodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    if let metro = venue.metro, !metro.isEmpty {
                        MetroList(stations: metro)
                    }
                }
                .padding(.horizontal, Spacing.gutterProduct)

                parameters(venue).padding(.horizontal, Spacing.gutterProduct)

                if let lat = venue.geo?.lat, let lng = venue.geo?.lng {
                    VenueMap(name: venue.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                        .padding(.horizontal, Spacing.gutterProduct)
                }

                if let html = venue.descriptionHtml, !html.isEmpty {
                    DescriptionSection(html: html).padding(.horizontal, Spacing.gutterProduct)
                }

                if let steps = venue.howToRent, !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Как арендовать")
                            .font(.pH3)
                            .foregroundStyle(Palette.textProduct)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HowToRentStep(number: index + 1, text: step)
                        }
                    }
                    .padding(.horizontal, Spacing.gutterProduct)
                }

                requestCard(venue).padding(.horizontal, Spacing.gutterProduct)

                if let similar = venue.similar, !similar.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: String(localized: "Похожие площадки"))
                            .padding(.horizontal, Spacing.gutterProduct)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(similar) { item in
                                    VenueCard(venue: item) { env.router.push(.venue(id: item.id)) }
                                        .frame(width: 300)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, Spacing.gutterProduct)
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                }
            }
            .padding(.bottom, Spacing.sectionLarge)
        }
    }

    private func parameters(_ venue: Venue) -> some View {
        // На крупных размерах шрифта плитки встают в столбец, иначе подписи ломаются по буквам.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            if let area = venue.area {
                parameter(value: "\(area) м²", title: String(localized: "площадь"))
            }
            if let capacity = venue.capacity {
                parameter(value: "\(capacity)", title: String(localized: "гостей"))
            }
            if let distance = venue.metro?.first?.distance {
                parameter(value: "\(distance) м", title: String(localized: "до метро"))
            }
        }
    }

    private func parameter(value: String, title: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(BrandFont.golos(17, .bold)).foregroundStyle(Palette.textProduct)
            Text(title).font(.aaCaption).foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
        .accessibilityElement(children: .combine)
    }

    /// Градиентная форма «Заявка на расчёт» (как на сайте).
    private func requestCard(_ venue: Venue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PriceTagView(tag: venue.price, numberFont: BrandFont.golos(24, .bold), color: .white, secondaryColor: .white.opacity(0.85))
            if let minHours = venue.minHours {
                Text("Минимум — \(minHours) ч").font(.aaBodySmall).foregroundStyle(.white.opacity(0.9))
            }
            Button {
                let subject = RequestSubject(
                    kind: .venue,
                    title: venue.name,
                    venueId: venue.id,
                    eventTypes: venue.eventTypes ?? [],
                    requiresDate: true,
                    minHoursNote: venue.minHours.map { String(localized: "Минимум — \($0) ч") }
                )
                env.router.requireLogin(isLoggedIn: env.auth.isLoggedIn) { request = subject }
            } label: {
                Text("Заявка на расчёт")
                    .font(.aaSubmit)
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(.white))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.leadGradient))
    }
}

/// Шаг «Как арендовать»: номер растёт вместе с Dynamic Type, VoiceOver читает «номер, текст» одним элементом.
private struct HowToRentStep: View {
    let number: Int
    let text: String
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 32

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(BrandFont.inter(14, .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: badgeSize, height: badgeSize)
                .background(Circle().fill(Palette.accentTint10))
            Text(text)
                .font(.pBody)
                .foregroundStyle(Palette.textProduct)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Скелетон карточки площадки: галерея 4:3, тип/название/адрес, плитки параметров.
private struct VenueDetailSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Rectangle()
                    .fill(Palette.bgTertiary.opacity(0.6))
                    .aspectRatio(MediaAspect.photo, contentMode: .fit)
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBlock(width: 80, height: 12)
                    SkeletonBlock(height: 24)
                    SkeletonBlock(width: 220, height: 14)
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonBlock(height: 64, radius: Radius.md)
                        }
                    }
                    .padding(.top, 6)
                    SkeletonBlock(height: 200, radius: Radius.card)
                        .padding(.top, 6)
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

/// Карта MapKit с пином; тап — открыть в Картах.
private struct VenueMap: View {
    let name: String
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Локация")
                .font(.pH3)
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))) {
                Marker(name, coordinate: coordinate)
                    .tint(Palette.accent)
            }
            .mapControlVisibility(.hidden)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .allowsHitTesting(false)
            // Карта — иллюстрация; действие одно, его даёт кнопка поверх (VoiceOver не должен
            // застревать в недоступной для жестов карте).
            .accessibilityHidden(true)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    Haptics.play(.selection)
                    openInMaps()
                } label: {
                    Label("Открыть в Картах", systemImage: "map")
                        .font(.aaCaption)
                        .foregroundStyle(Palette.textProduct)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .brandGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Text(verbatim: "\(String(localized: "Открыть в Картах")): \(name)"))
                .padding(6)
            }
        }
    }

    private func openInMaps() {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "q", value: name),
        ]
        if let url = components?.url { UIApplication.shared.open(url) }
    }
}
