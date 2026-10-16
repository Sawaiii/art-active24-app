import MapKit
import SwiftUI

/// Карточка площадки: галерея, тип, адрес, метро с цветом линии, параметры, карта с пином,
/// описание, «Как арендовать», форма «Заявка на расчёт», похожие площадки.
struct VenueDetailView: View {
    @State private var viewModel: VenueDetailViewModel
    @State private var request: RequestSubject?
    @Environment(AppEnvironment.self) private var env

    init(viewModel: VenueDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ScrollView { ListSkeleton(rows: 6).padding(Spacing.gutter) }
            case let .error(message):
                ErrorStateView(message: message) { await viewModel.load() }
            case .empty:
                EmptyStateView(systemImage: "building.2", title: String(localized: "Площадка не найдена"))
            case let .content(venue):
                content(venue)
            }
        }
        .background(Palette.page)
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
            VStack(alignment: .leading, spacing: 24) {
                GalleryPager(items: GalleryItem.from(urls: venue.photos ?? []), aspectRatio: 4 / 3)

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
                .padding(.horizontal, Spacing.gutter)

                parameters(venue).padding(.horizontal, Spacing.gutter)

                if let lat = venue.geo?.lat, let lng = venue.geo?.lng {
                    VenueMap(name: venue.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng))
                        .padding(.horizontal, Spacing.gutter)
                }

                if let html = venue.descriptionHtml, !html.isEmpty {
                    DescriptionSection(html: html).padding(.horizontal, Spacing.gutter)
                }

                if let steps = venue.howToRent, !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Как арендовать").font(.pH3).foregroundStyle(Palette.textProduct)
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text(verbatim: "\(index + 1)")
                                    .font(BrandFont.inter(14, .bold))
                                    .foregroundStyle(Palette.accent)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Palette.accentTint10))
                                Text(step).font(.pBody).foregroundStyle(Palette.textProduct)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                }

                requestCard(venue).padding(.horizontal, Spacing.gutter)

                if let similar = venue.similar, !similar.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: String(localized: "Похожие площадки"))
                            .padding(.horizontal, Spacing.gutter)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(similar) { item in
                                    VenueCard(venue: item) { env.router.push(.venue(id: item.id)) }
                                        .frame(width: 300)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, Spacing.gutter)
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func parameters(_ venue: Venue) -> some View {
        HStack(spacing: 10) {
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
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
        .accessibilityElement(children: .combine)
    }

    /// Градиентная форма «Заявка на расчёт» (как на сайте).
    private func requestCard(_ venue: Venue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PriceTagView(tag: venue.price, numberFont: BrandFont.golos(24, .bold), color: .white)
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

/// Карта MapKit с пином; тап — открыть в Картах.
private struct VenueMap: View {
    let name: String
    let coordinate: CLLocationCoordinate2D

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Локация").font(.pH3).foregroundStyle(Palette.textProduct)
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1200, longitudinalMeters: 1200))) {
                Marker(name, coordinate: coordinate)
                    .tint(Palette.accent)
            }
            .mapControlVisibility(.hidden)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .allowsHitTesting(false)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    openInMaps()
                } label: {
                    Label("Открыть в Картах", systemImage: "map")
                        .font(.aaCaption)
                        .foregroundStyle(Palette.textProduct)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .brandGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(PressableStyle())
                .padding(10)
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
