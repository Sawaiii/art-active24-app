import MapKit
import SwiftUI

/// Машина с заказом на карте (пока статус «В пути»): точка, круг точности, курс,
/// «обновлено N мин назад», ожидаемое прибытие. Обновляется каждые 15 с, пока карточка на экране.
struct VehicleMapCard: View {
    let orderId: Int
    let orders: OrdersStore

    @State private var location: VehicleLocation?
    @State private var didFail = false
    @State private var position: MapCameraPosition = .automatic
    @State private var hasCentered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let refreshInterval: Duration = .seconds(15)
    private static let spanMeters: CLLocationDistance = 1600
    private static let mapHeight: CGFloat = 220

    init(orderId: Int, orders: OrdersStore) {
        self.orderId = orderId
        self.orders = orders
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            mapArea
            infoRow
        }
        .padding(.vertical, 6)
        .task { await poll() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orderDetail.vehicleMap")
    }

    // MARK: - Карта

    @ViewBuilder
    private var mapArea: some View {
        if let location, let coordinate = location.coordinate {
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                if let accuracy = location.accuracy, accuracy > 0 {
                    MapCircle(center: coordinate, radius: accuracy)
                        .stroke(Palette.accent.opacity(0.45), lineWidth: 1)
                        .foregroundStyle(Palette.accent.opacity(0.15))
                }
                Annotation(String(localized: "Машина"), coordinate: coordinate, anchor: .center) {
                    VehicleMarker(heading: location.heading, isStale: location.status == .unknown)
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: Self.mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if position.positionedByUser {
                    Button {
                        Haptics.play(.selection)
                        center(on: coordinate, animated: true)
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 44, height: 44)
                            .brandGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityLabel(Text("Показать машину"))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Карта: машина с заказом"))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: location == nil && !didFail ? "location.magnifyingglass" : "location.slash")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Group {
                if location == nil && !didFail {
                    Text("Ищем машину…")
                } else if didFail && location == nil {
                    Text("Не удалось получить положение машины. Попробуем ещё раз через несколько секунд.")
                } else {
                    Text("Покажем машину, как только водитель включит геопозицию")
                }
            }
            .font(.aaBodySmall)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surfaceMuted))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Подписи

    private var infoRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(BrandFont.golos(15, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.textProduct)
                if let eta = location?.eta, location?.status == .enRoute {
                    Text("Прибытие ~ \(eta, style: .time)")
                        .font(.aaBodySmall)
                        .foregroundStyle(Palette.textStrong)
                }
                if let updatedAt = location?.updatedAt {
                    HStack(spacing: 4) {
                        Text("Обновлено")
                        Text(updatedAt, format: .relative(presentation: .named))
                    }
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
                }
                if let vehicleText {
                    Text(verbatim: vehicleText)
                        .font(.aaCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusTitle: String {
        switch location?.status {
        case .enRoute?: return String(localized: "В пути")
        case .arrived?: return String(localized: "Машина на месте")
        case .unknown?: return String(localized: "Нет связи с машиной")
        case nil: return didFail ? String(localized: "Нет связи с машиной") : String(localized: "В пути")
        }
    }

    private var statusSymbol: String {
        switch location?.status {
        case .arrived?: return "mappin.and.ellipse"
        case .unknown?: return "antenna.radiowaves.left.and.right.slash"
        default: return "box.truck.fill"
        }
    }

    private var vehicleText: String? {
        let parts = [location?.vehicle, location?.driverName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Обновление

    private func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }

    private func refresh() async {
        do {
            let fresh = try await orders.vehicle(orderId: orderId)
            location = fresh
            didFail = false
            if let coordinate = fresh.coordinate, !position.positionedByUser {
                center(on: coordinate, animated: hasCentered)
                hasCentered = true
            }
        } catch {
            guard !error.isCancellation else { return }
            didFail = true
        }
    }

    /// Камера следует за машиной, пока пользователь сам не сдвинул карту.
    private func center(on coordinate: CLLocationCoordinate2D, animated: Bool) {
        let region = MapCameraPosition.region(MKCoordinateRegion(
            center: coordinate, latitudinalMeters: Self.spanMeters, longitudinalMeters: Self.spanMeters
        ))
        if animated, !reduceMotion {
            withAnimation(.easeInOut(duration: 0.6)) { position = region }
        } else {
            position = region
        }
    }
}

/// Маркер машины: фиолетовый круг с грузовиком и стрелка курса по окружности.
private struct VehicleMarker: View {
    let heading: Double?
    let isStale: Bool

    var body: some View {
        ZStack {
            if let heading {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 64, height: 64, alignment: .top)
                    .rotationEffect(.degrees(heading))
            }
            Circle()
                .fill(isStale ? Palette.textTertiary : Palette.accent)
                .frame(width: 40, height: 40)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            Image(systemName: "box.truck.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}

private extension VehicleLocation {
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lng, (-90...90).contains(lat), (-180...180).contains(lng) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
