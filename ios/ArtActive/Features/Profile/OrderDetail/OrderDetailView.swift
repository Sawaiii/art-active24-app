import Observation
import QuickLook
import SwiftUI

// MARK: - Модель экрана

@MainActor
@Observable
final class OrderDetailViewModel {
    /// Разделы карточки заказа.
    enum Tab: Hashable, CaseIterable {
        case overview, composition, documents

        var title: String {
            switch self {
            case .overview: return String(localized: "Обзор")
            case .composition: return String(localized: "Состав")
            case .documents: return String(localized: "Документы")
            }
        }
    }

    let orderId: Int
    private(set) var state: ViewState<Order> = .loading
    private(set) var isCancelling = false
    private(set) var actionError: String?
    private(set) var composition: ViewState<OrderComposition> = .loading
    private(set) var documents: ViewState<[OrderDocument]> = .loading
    var tab: Tab = .overview

    @ObservationIgnored let orders: OrdersStore
    @ObservationIgnored private var compositionRequested = false
    @ObservationIgnored private var documentsRequested = false

    init(orderId: Int, orders: OrdersStore) {
        self.orderId = orderId
        self.orders = orders
        if let cached = orders.orders.first(where: { $0.id == orderId }) {
            state = .content(cached)
        }
    }

    func load() async {
        do {
            let order = try await orders.order(id: orderId)
            state = .content(order)
            orders.markSeen(order)
        } catch {
            guard !error.isCancellation else { return }
            if state.content == nil { state = .error(error.userMessage) }
        }
    }

    /// Разделы «Состав» и «Документы» грузятся при первом открытии.
    func loadTabIfNeeded() async {
        switch tab {
        case .overview:
            break
        case .composition:
            guard !compositionRequested else { return }
            await loadComposition()
        case .documents:
            guard !documentsRequested else { return }
            await loadDocuments()
        }
    }

    /// Pull-to-refresh: карточка заказа и открытый раздел.
    func refresh() async {
        await load()
        switch tab {
        case .overview: break
        case .composition: await loadComposition()
        case .documents: await loadDocuments()
        }
    }

    func loadComposition() async {
        compositionRequested = true
        do {
            let value = try await orders.composition(orderId: orderId)
            composition = value.isEmpty ? .empty : .content(value)
        } catch {
            guard !error.isCancellation else {
                compositionRequested = false
                return
            }
            if composition.content == nil { composition = .error(error.userMessage) }
        }
    }

    func loadDocuments() async {
        documentsRequested = true
        do {
            let value = try await orders.documents(orderId: orderId)
            documents = value.isEmpty ? .empty : .content(value)
        } catch {
            guard !error.isCancellation else {
                documentsRequested = false
                return
            }
            if documents.content == nil { documents = .error(error.userMessage) }
        }
    }

    func cancel() async {
        isCancelling = true
        actionError = nil
        defer { isCancelling = false }
        do {
            state = .content(try await orders.cancel(id: orderId))
            Haptics.play(.success)
        } catch {
            actionError = error.userMessage
            Haptics.play(.error)
        }
    }

    /// Текст для «Поделиться составом»: состав из КП, если он уже загружен, иначе позиции заказа.
    func shareText(for order: Order) -> String? {
        if let composition = composition.content {
            return CompositionShareText.make(composition, orderNumber: order.number)
        }
        return CompositionShareText.make(order: order)
    }
}

/// Черновик отзыва для шита (оценка, выбранная на карточке).
struct ReviewDraft: Identifiable {
    let id = UUID()
    let rating: Int
    let text: String?
}

// MARK: - Экран

/// Детали заказа: шапка и три раздела — «Обзор» (статус, машина на карте, отзыв, претензия,
/// позиции, действия), «Состав» (из КП) и «Документы».
struct OrderDetailView: View {
    @State private var viewModel: OrderDetailViewModel
    @State private var isCancelConfirming = false
    @State private var isClaimPresented = false
    @State private var reviewDraft: ReviewDraft?
    @State private var previewURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: OrderDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ScrollView { ListSkeleton().padding(Spacing.gutter) }
            case let .error(message):
                ErrorStateView(message: message) { await viewModel.load() }
            case .empty:
                EmptyStateView(systemImage: "shippingbox", title: String(localized: "Заказ не найден"))
            case let .content(order):
                content(order)
            }
        }
        .navigationTitle(Text(viewModel.state.content?.number ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let order = viewModel.state.content {
                    moreMenu(order)
                }
            }
        }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        .onChange(of: viewModel.tab) { _, _ in
            Haptics.play(.selection)
            Task { await viewModel.loadTabIfNeeded() }
        }
        .confirmationDialog(Text("Отменить заявку?"), isPresented: $isCancelConfirming, titleVisibility: .visible) {
            Button("Отменить заявку", role: .destructive) {
                Task { await viewModel.cancel() }
            }
        } message: {
            Text("Менеджер получит уведомление об отмене.")
        }
        .sheet(isPresented: $isClaimPresented, onDismiss: reloadOrder) {
            ClaimFormSheet(viewModel: ClaimFormViewModel(orderId: viewModel.orderId, orders: viewModel.orders))
        }
        .sheet(item: $reviewDraft, onDismiss: reloadOrder) { draft in
            ReviewFormSheet(viewModel: ReviewFormViewModel(
                orderId: viewModel.orderId, orders: viewModel.orders, rating: draft.rating, text: draft.text
            ))
        }
        .quickLookPreview($previewURL)
    }

    private func reloadOrder() {
        Task { await viewModel.load() }
    }

    private func content(_ order: Order) -> some View {
        List {
            Section {
                OrderHeaderCard(order: order)
            }

            Section {
                Picker(selection: $viewModel.tab) {
                    ForEach(OrderDetailViewModel.Tab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                } label: {
                    Text("Раздел заказа")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("orderDetail.tabs")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            switch viewModel.tab {
            case .overview:
                OrderOverviewSections(
                    order: order,
                    orders: viewModel.orders,
                    isCancelling: viewModel.isCancelling,
                    actionError: viewModel.actionError,
                    onCancel: { isCancelConfirming = true },
                    onReview: { rating in reviewDraft = ReviewDraft(rating: rating, text: order.review?.text) },
                    onClaim: { isClaimPresented = true }
                )
            case .composition:
                OrderCompositionSections(order: order, state: viewModel.composition) {
                    await viewModel.loadComposition()
                }
            case .documents:
                OrderDocumentsSections(state: viewModel.documents, onPreview: { previewURL = $0 }) {
                    await viewModel.loadDocuments()
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(Motion.fast(reduceMotion), value: viewModel.tab)
    }

    /// «…» в навбаре: редкие действия, в том числе «Что-то пошло не так?».
    private func moreMenu(_ order: Order) -> some View {
        Menu {
            if let text = viewModel.shareText(for: order) {
                ShareLink(item: text) {
                    Label("Поделиться составом", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                viewModel.tab = .documents
            } label: {
                Label("Документы", systemImage: "doc.text")
            }
            if order.canClaim == true {
                Divider()
                Button {
                    isClaimPresented = true
                } label: {
                    Label("Что-то пошло не так?", systemImage: "exclamationmark.bubble")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel(Text("Ещё"))
        }
        .accessibilityIdentifier("orderDetail.menu")
    }
}

/// Шапка заказа: статус, даты, доставка, когда создан.
struct OrderHeaderCard: View {
    let order: Order

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OrderStatusChip(status: order.status, label: order.statusLabel)
            if let dates = DateText.range(from: order.eventDate, to: order.eventDateTo) {
                Label(dates, systemImage: "calendar")
            }
            if let delivery = order.delivery {
                Label(deliveryText(delivery), systemImage: delivery.method == .pickup ? "figure.walk" : "truck.box")
            }
            Text("Создан \(DateText.dateTime(order.createdAt))")
                .font(.aaCaption)
                .foregroundStyle(Palette.textSecondary)
        }
        .font(.aaBodySmall)
        .padding(.vertical, 4)
    }

    private func deliveryText(_ delivery: OrderDelivery) -> String {
        switch delivery.method {
        case .pickup?: return String(localized: "Самовывоз")
        default:
            let address = delivery.address ?? ""
            return address.isEmpty ? String(localized: "Доставка") : String(localized: "Доставка: \(address)")
        }
    }
}
