import SwiftUI

// MARK: - Переход «плитка → карточка» (zoom, iOS 18+)

private struct ZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Пространство имён для navigationTransition(.zoom) в пределах стека таба.
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

private struct ZoomSourceModifier: ViewModifier {
    let id: String
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            if #available(iOS 18.0, *) {
                content.matchedTransitionSource(id: id, in: namespace)
            } else {
                content
            }
        } else {
            content
        }
    }
}

private struct ZoomDestinationModifier: ViewModifier {
    let id: String
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            if #available(iOS 18.0, *) {
                content.navigationTransition(.zoom(sourceID: id, in: namespace))
            } else {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func zoomTransitionSource(id: String) -> some View { modifier(ZoomSourceModifier(id: id)) }
    func zoomTransitionDestination(id: String) -> some View { modifier(ZoomDestinationModifier(id: id)) }
}

enum ZoomID {
    static func product(_ id: Int) -> String { "product-\(id)" }
    static func venue(_ id: Int) -> String { "venue-\(id)" }
}

// MARK: - Карточка листинга (.aa-card)

enum ProductGrid {
    static let columns = [
        GridItem(.flexible(), spacing: Spacing.gridGap, alignment: .top),
        GridItem(.flexible(), spacing: Spacing.gridGap, alignment: .top),
    ]
}

/// Плитка товара: фото 1:1 r16 на #F1F1F5, бейдж, название, «от 1 400 ₽». Без тени/рамки.
struct ProductCard: View {
    let product: ProductSummary
    var isFavorite = false
    var onFavorite: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.cardInner) {
            // Большая ава сайта 600×600 — квадрат с заполнением; если пришло фото 800×600 — целиком на подложке.
            AspectImage(url: product.image?.resolvedURL, aspect: MediaAspect.square, cornerRadius: Radius.card, maxPixel: 520, fitMismatched: true)
                .overlay(alignment: .topLeading) {
                    if let badge = product.badge {
                        BadgeView(badge).padding(8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let onFavorite {
                        FavoriteButton(isOn: isFavorite, size: 32, action: onFavorite).padding(6)
                    }
                }
                .zoomTransitionSource(id: ZoomID.product(product.id))

            Text(product.name)
                .font(.aaCardTitle)
                .foregroundStyle(Palette.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            PriceTagView(tag: product.price)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        [product.badge?.text, product.name, Money.tag(product.price)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

/// Быстрый просмотр по долгому нажатию (превью contextMenu).
struct ProductPeekView: View {
    let product: ProductSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RemoteImage(url: product.image?.resolvedURL, maxPixel: 700)
                .frame(width: 300, height: 300)
            VStack(alignment: .leading, spacing: 6) {
                Text(product.name)
                    .font(.pTitle)
                    .foregroundStyle(Palette.textProduct)
                    .lineLimit(3)
                PriceTagView(tag: product.price)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 300)
        .background(Palette.surface)
    }
}

/// Горизонтальная лента карточек («Новинки», «Похожие», «Вы смотрели»).
struct ProductCarousel: View {
    let products: [ProductSummary]
    var cardWidth: CGFloat = 160
    let onSelect: (ProductSummary) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(products) { product in
                    Button { onSelect(product) } label: {
                        ProductCard(product: product).frame(width: cardWidth)
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
