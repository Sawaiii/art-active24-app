import Observation
import SwiftUI

@MainActor
@Observable
final class CartViewModel {
    struct UndoState: Equatable {
        let id = UUID()
        let message: String
        let item: CartItemInput
        let index: Int
    }

    let cart: CartStore
    let favorites: FavoritesStore
    private(set) var undo: UndoState?

    @ObservationIgnored private var undoTask: Task<Void, Never>?
    private static let undoDuration: Duration = .seconds(4)

    init(cart: CartStore, favorites: FavoritesStore) {
        self.cart = cart
        self.favorites = favorites
    }

    func remove(_ item: CartItemInput) {
        let name = cart.quoteLine(for: item)?.productName ?? String(localized: "Позиция")
        guard let removed = cart.remove(item.lineKey) else { return }
        Haptics.play(.swipeThreshold)
        showUndo(UndoState(message: String(localized: "«\(name)» удалён из корзины"), item: removed.item, index: removed.index))
    }

    func moveToFavorites(_ item: CartItemInput) {
        guard let line = cart.quoteLine(for: item) else { return }
        let summary = ProductSummary(
            id: item.productId,
            slug: line.productSlug ?? "",
            name: line.productName,
            image: line.image,
            price: nil,
            badge: nil,
            template: .unknown
        )
        if !favorites.contains(item.productId) { favorites.toggle(summary) }
        Haptics.play(.favorite)
        guard let removed = cart.remove(item.lineKey) else { return }
        showUndo(UndoState(message: String(localized: "Перенесено в избранное"), item: removed.item, index: removed.index))
    }

    func undoRemoval() {
        guard let undo else { return }
        cart.restore(undo.item, at: undo.index)
        self.undo = nil
        undoTask?.cancel()
    }

    func setQty(_ qty: Int, for item: CartItemInput) {
        cart.setQty(qty, for: item.lineKey)
    }

    private func showUndo(_ state: UndoState) {
        undo = state
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: CartViewModel.undoDuration)
            guard !Task.isCancelled else { return }
            withAnimation { self?.undo = nil }
        }
    }
}

/// Корзина: серверный quote, свайп — удалить (Undo 4 с) / в избранное, степпер, итог,
/// плашка «Цены не окончательные…», «Оставить заявку».
struct CartView: View {
    @State private var viewModel: CartViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(InfoStore.self) private var info

    init(viewModel: CartViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var cart: CartStore { viewModel.cart }

    var body: some View {
        Group {
            if cart.isEmpty {
                ScrollView {
                    EmptyStateView(
                        systemImage: "cart",
                        title: String(localized: "Корзина пуста"),
                        message: String(localized: "Добавьте мебель, аттракционы или кейтеринг — менеджер соберёт предложение"),
                        actionTitle: String(localized: "Перейти в каталог")
                    ) { env.router.selectedTab = .catalog }
                    .padding(.top, 60)
                }
            } else {
                list
            }
        }
        .background(Palette.catalogPage)
        .navigationTitle(Text("Корзина"))
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .bottom) {
            if let undo = viewModel.undo {
                UndoToast(message: undo.message) { withAnimation { viewModel.undoRemoval() } }
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(undo.id)
            }
        }
        .animation(.snappy, value: viewModel.undo)
        .task { await cart.refreshQuote() }
    }

    private var list: some View {
        List {
            Section {
                ForEach(cart.items, id: \.lineKey) { item in
                    CartRow(item: item, line: cart.quoteLine(for: item), isQuoteLoading: cart.quoteStatus == .loading) { qty in
                        viewModel.setQty(qty, for: item)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        env.router.push(.product(id: item.productId, preselect: ProductPreselection(complectId: item.complectId, subId: item.subId, priceType: item.priceType)))
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation { viewModel.remove(item) }
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            withAnimation { viewModel.moveToFavorites(item) }
                        } label: {
                            Label("В избранное", systemImage: "heart")
                        }
                        .tint(Palette.accent)
                    }
                    .listRowBackground(Palette.surface)
                }
            } footer: {
                Text("Свайп влево — удалить, вправо — в избранное.")
            }

            Section {
                summary
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                // Один текст: серверный cartNotice целиком либо локальная пара «заголовок + пояснение».
                InfoNote(
                    title: info.info.cartNotice ?? String(localized: "Цены не окончательные — это список интересующих вас позиций."),
                    message: info.info.cartNotice == nil
                        ? String(localized: "Оставьте заявку, и менеджер свяжется с вами, подберёт условия и сформирует персональное предложение.")
                        : nil
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable {
            Haptics.play(.refresh)
            await cart.refreshQuote()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Итого")
                    .font(BrandFont.golos(17))
                    .foregroundStyle(Palette.textStrong)
                Spacer()
                if let quote = cart.quote, cart.quoteStatus != .loading || quote.total > 0 {
                    Text(Money.rub(quote.total))
                        .font(.aaCartTotal)
                        .foregroundStyle(Palette.textStrong)
                        .contentTransition(.numericText(value: Double(quote.total)))
                        .animation(.snappy, value: quote.total)
                } else {
                    SkeletonBlock(width: 110, height: 24).shimmering()
                }
            }
            if cart.quote?.hasOnRequest == true {
                Text("Часть позиций — по запросу: их стоимость уточнит менеджер.")
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            if case let .failed(message) = cart.quoteStatus {
                HStack {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.aaCaption)
                        .foregroundStyle(Palette.error)
                    Spacer()
                    Button("Повторить") { Task { await cart.refreshQuote() } }
                        .buttonStyle(LinkButtonStyle(font: .aaCaption))
                }
            }
            Button {
                env.router.requireLogin(isLoggedIn: env.auth.isLoggedIn) {
                    env.router.push(.checkout, in: .cart)
                }
            } label: {
                Text("Оставить заявку")
            }
            .buttonStyle(PrimaryButtonStyle(height: 54, radius: Radius.md, font: .aaSubmit))
            .disabled(cart.quote?.lines.contains(where: { !$0.available }) == true)
            .accessibilityIdentifier("cart.checkout")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
    }
}

/// Строка корзины: фото, название, комплект, «Аренда, 2 д», допы, степпер, цена за ед., сумма.
private struct CartRow: View {
    let item: CartItemInput
    let line: QuoteLine?
    let isQuoteLoading: Bool
    let onQty: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: line?.image?.resolvedURL, contentMode: .fit, maxPixel: 240, placeholder: Palette.imagePlaceholder)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                if let line {
                    Text(line.productName)
                        .font(BrandFont.golos(14, .medium))
                        .foregroundStyle(Palette.textStrong)
                        .lineLimit(2)
                    Text([line.complectTitle, line.subTitle].compactMap { $0 }.joined(separator: " · "))
                        .font(.aaCaption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                    // Чип срока — только когда есть время аренды («Аренда, 3 д»).
                    if let timeLabel = line.timeLabel, !timeLabel.isEmpty {
                        let mode = [line.priceLabel, timeLabel].compactMap { $0 }.joined(separator: ", ")
                        Label(mode, systemImage: "clock")
                            .font(BrandFont.golos(12, .medium, relativeTo: .caption))
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: Radius.xs).fill(Palette.accentTint08))
                    }
                    if let extras = line.extras, !extras.isEmpty {
                        Text(extras.compactMap { extra -> String? in
                            guard let name = extra.name else { return nil }
                            return (extra.qty ?? 1) > 1 ? "+ \(name) × \(extra.qty ?? 1)" : "+ \(name)"
                        }.joined(separator: "\n"))
                        .font(.aaCaption)
                        .foregroundStyle(Palette.textSecondary)
                    }
                    if !line.available || line.warning != nil {
                        Label(line.warning ?? String(localized: "Снят с продажи — удалите позицию"), systemImage: "exclamationmark.triangle.fill")
                            .font(.aaCaption)
                            .foregroundStyle(Palette.warning)
                    }
                } else {
                    SkeletonBlock(height: 14)
                    SkeletonBlock(width: 120, height: 12)
                }

                HStack(alignment: .center, spacing: 10) {
                    if item.menu == nil {
                        QtyStepper(value: item.qty, minimum: 1, unit: nil, compact: true, onChange: onQty)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 2) {
                        if let line {
                            if line.onRequest == true {
                                Text("по запросу").font(.aaCartItemPrice).foregroundStyle(Palette.textStrong)
                            } else {
                                Text(Money.rub(line.total))
                                    .font(.aaCartItemPrice)
                                    .foregroundStyle(Palette.textStrong)
                                    .contentTransition(.numericText(value: Double(line.total)))
                                if item.menu == nil {
                                    Text(verbatim: "\(Money.rub(line.unitPrice))/\(line.qtyUnit ?? String(localized: "ед"))")
                                        .font(BrandFont.golos(10, relativeTo: .caption2))
                                        .foregroundStyle(Palette.muted2)
                                }
                            }
                        }
                    }
                    .opacity(isQuoteLoading ? 0.5 : 1)
                    .animation(.snappy, value: line?.total)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Корзина") {
    let env = AppEnvironment.preview()
    return NavigationStack {
        CartView(viewModel: CartViewModel(cart: env.cart, favorites: env.favorites))
    }
    .previewEnvironment(env)
}
#endif
