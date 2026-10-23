import SwiftUI

/// Плитка товара для листингов: переход в карточку, сердечко, long-press превью
/// с действиями «В корзину» (открывает конфигурацию), «В избранное», «Поделиться».
struct ProductTile: View {
    let product: ProductSummary
    var width: CGFloat?

    @Environment(Router.self) private var router
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        let isFavorite = favorites.contains(product.id)
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                ProductCard(product: product)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("product.tile.\(product.id)")

            FavoriteButton(isOn: isFavorite, size: 32) {
                favorites.toggle(product)
            }
            .padding(6)
        }
        .frame(width: width)
        .contextMenu {
            Button(action: open) {
                Label("В корзину", systemImage: "cart.badge.plus")
            }
            Button {
                Haptics.play(.favorite)
                favorites.toggle(product)
            } label: {
                if isFavorite {
                    Label("Убрать из избранного", systemImage: "heart.slash")
                } else {
                    Label("В избранное", systemImage: "heart")
                }
            }
            if let url = URL(string: "/\(product.slug)/", relativeTo: AppConfig.siteURL)?.absoluteURL {
                ShareLink(item: url, subject: Text(product.name)) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
            }
        } preview: {
            ProductPeekView(product: product)
        }
    }

    private func open() {
        router.push(.product(id: product.id, preselect: nil))
    }
}

/// Сетка 2 колонки из плиток.
struct ProductGridView: View {
    let products: [ProductSummary]
    var onAppearLast: (() -> Void)?

    var body: some View {
        LazyVGrid(columns: ProductGrid.columns, spacing: 20) {
            ForEach(products) { product in
                ProductTile(product: product)
                    .onAppear {
                        if product.id == products.last?.id { onAppearLast?() }
                    }
            }
        }
    }
}

/// Логотип мессенджера Max (из шапки сайта, «Написать в Max») — шаблонный вектор в Assets.
enum MaxIcon {
    static let assetName = "IconMax"
}

/// «Связь с нами»: звонок, Telegram, WhatsApp, Max, почта (как меню шапки сайта).
struct ContactMenuButton<LabelContent: View>: View {
    @Environment(InfoStore.self) private var info
    @ViewBuilder let label: LabelContent

    var body: some View {
        Menu {
            if let phone = info.phoneURL {
                Button { info.open(phone) } label: {
                    Label("Позвонить", systemImage: "phone")
                }
            }
            if let telegram = info.telegramURL {
                Button { info.open(telegram) } label: {
                    Label("Telegram", systemImage: "paperplane")
                }
            }
            if let whatsapp = info.whatsappURL {
                Button { info.open(whatsapp) } label: {
                    Label("WhatsApp", systemImage: "message")
                }
            }
            if let max = info.maxURL {
                Button { info.open(max) } label: {
                    Label {
                        Text(verbatim: "Max")
                    } icon: {
                        Image(MaxIcon.assetName)
                    }
                }
                .accessibilityIdentifier("contact.max")
            }
            if let email = info.emailURL {
                Button { info.open(email) } label: {
                    Label("Написать на почту", systemImage: "envelope")
                }
            }
        } label: {
            label
        }
        .simultaneousGesture(TapGesture().onEnded { Haptics.play(.selection) })
    }
}

/// Кнопки связи в строку (карточка товара, заказ, профиль).
struct ContactButtonsRow: View {
    @Environment(InfoStore.self) private var info
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 19

    var body: some View {
        HStack(spacing: 10) {
            if let phone = info.phoneURL {
                contactButton(String(localized: "Позвонить"), systemImage: "phone.fill") { info.open(phone) }
            }
            if let telegram = info.telegramURL {
                contactButton("Telegram", systemImage: "paperplane.fill") { info.open(telegram) }
            }
            if let whatsapp = info.whatsappURL {
                contactButton("WhatsApp", icon: Image(systemName: "message.fill")) { info.open(whatsapp) }
            }
            if let max = info.maxURL {
                contactButton("Max", icon: Image(MaxIcon.assetName), iconIsAsset: true) { info.open(max) }
                    .accessibilityIdentifier("contact.max")
            }
        }
    }

    private func contactButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        contactButton(title, icon: Image(systemName: systemImage), action: action)
    }

    private func contactButton(_ title: String, icon: Image, iconIsAsset: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            VStack(spacing: 6) {
                if iconIsAsset {
                    // Вектор из Assets не масштабируется шрифтом — размер как у символа 17 pt.
                    icon
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                } else {
                    icon.font(.system(size: 17, weight: .semibold))
                }
                Text(title).font(.aaCaption).lineLimit(1)
            }
            .foregroundStyle(Palette.accent)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.accentTint08))
        }
        .buttonStyle(PressableStyle())
    }
}
