import Observation
import SwiftUI

/// Цвет статус-чипа.
enum OrderStatusStyle {
    static func color(_ status: OrderStatus) -> Color {
        switch status {
        case .processing: return Palette.warning
        case .confirmed, .preparing: return Palette.accent
        case .delivering, .inProgress: return Color(light: 0x007AFF, dark: 0x0A84FF)
        case .completed: return Palette.success
        case .cancelled, .unknown: return Palette.textTertiary
        }
    }

    static func symbol(_ status: OrderStatus) -> String {
        switch status {
        case .processing: return "hourglass"
        case .confirmed: return "checkmark.seal"
        case .preparing: return "shippingbox"
        case .delivering: return "truck.box"
        case .inProgress: return "sparkles"
        case .completed: return "flag.checkered"
        case .cancelled: return "xmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct OrderStatusChip: View {
    let status: OrderStatus
    let label: String

    var body: some View {
        Label {
            // Локальная подпись по статусу; серверная — только для неизвестного статуса.
            Text(status != .unknown || label.isEmpty ? status.title : label)
        } icon: {
            Image(systemName: OrderStatusStyle.symbol(status))
        }
        .font(BrandFont.golos(12, .semibold, relativeTo: .caption))
        .foregroundStyle(OrderStatusStyle.color(status))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(OrderStatusStyle.color(status).opacity(0.12)))
    }
}

/// «Мои заказы» со статус-чипами и отметкой непрочитанных изменений.
struct OrdersView: View {
    @Environment(OrdersStore.self) private var orders
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            switch orders.status {
            case .idle where orders.orders.isEmpty, .loading where orders.orders.isEmpty:
                ScrollView { ListSkeleton().padding(Spacing.gutter) }
            case let .failed(message) where orders.orders.isEmpty:
                ErrorStateView(message: message) { await orders.load() }
            default:
                if orders.orders.isEmpty {
                    EmptyStateView(
                        systemImage: "shippingbox",
                        title: String(localized: "Заказов пока нет"),
                        message: String(localized: "Соберите корзину и оставьте заявку — она появится здесь"),
                        actionTitle: String(localized: "Перейти в каталог")
                    ) { router.selectedTab = .catalog }
                } else {
                    list
                }
            }
        }
        .navigationTitle(Text("Мои заказы"))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            Haptics.play(.refresh)
            await orders.load()
        }
        .task { await orders.load() }
    }

    private var list: some View {
        List {
            ForEach(orders.orders) { order in
                NavigationLink(value: Route.order(id: order.id)) {
                    OrderRow(order: order, isUnseen: orders.isUnseen(order))
                }
                .task {
                    if order.id == orders.orders.last?.id { await orders.loadMore() }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct OrderRow: View {
    let order: Order
    let isUnseen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(order.number)
                    .font(BrandFont.golos(16, .semibold))
                    .foregroundStyle(Palette.textProduct)
                if isUnseen {
                    Circle().fill(Palette.accent).frame(width: 8, height: 8)
                        .accessibilityLabel(Text("Есть изменения"))
                }
                Spacer()
                OrderStatusChip(status: order.status, label: order.statusLabel)
            }
            if let subject = order.subject ?? order.lines.first?.productName {
                Text(subject)
                    .font(.aaBodySmall)
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
            }
            HStack {
                Text(DateText.range(from: order.eventDate, to: order.eventDateTo) ?? DateText.dateTime(order.createdAt))
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if order.total > 0 {
                    Text(Money.rub(order.total))
                        .font(.aaCartItemPrice)
                        .foregroundStyle(Palette.textStrong)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Детали заказа

@MainActor
@Observable
final class OrderDetailViewModel {
    let orderId: Int
    private(set) var state: ViewState<Order> = .loading
    private(set) var isCancelling = false
    private(set) var actionError: String?

    @ObservationIgnored private let orders: OrdersStore

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
}

/// Детали заказа: таймлайн статусов, позиции, повтор, отмена (пока «В обработке»), связь.
struct OrderDetailView: View {
    @State private var viewModel: OrderDetailViewModel
    @State private var isCancelConfirming = false
    @Environment(CartStore.self) private var cart
    @Environment(Router.self) private var router

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
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
        .confirmationDialog(Text("Отменить заявку?"), isPresented: $isCancelConfirming, titleVisibility: .visible) {
            Button("Отменить заявку", role: .destructive) {
                Task { await viewModel.cancel() }
            }
        } message: {
            Text("Менеджер получит уведомление об отмене.")
        }
    }

    private func content(_ order: Order) -> some View {
        List {
            Section {
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

            Section {
                StatusTimeline(order: order)
            } header: {
                Text("Статус")
            }

            if !order.lines.isEmpty {
                Section {
                    ForEach(Array(order.lines.enumerated()), id: \.offset) { _, line in
                        OrderLineRow(line: line)
                    }
                    HStack {
                        Text("Итого").font(BrandFont.golos(17, .semibold))
                        Spacer()
                        Text(Money.rub(order.total)).font(.aaCartTotal)
                    }
                    if order.hasOnRequest == true {
                        Text("Часть позиций — по запросу.").font(.aaCaption).foregroundStyle(Palette.textSecondary)
                    }
                } header: {
                    Text("Состав")
                } footer: {
                    Text("Цены зафиксированы на момент оформления.")
                }
            } else if let subject = order.subject {
                Section {
                    Text(subject)
                } header: {
                    Text("Заявка")
                }
            }

            if let comment = order.comment, !comment.isEmpty {
                Section {
                    Text(comment)
                } header: {
                    Text("Комментарий")
                }
            }

            Section {
                if !order.repeatableItems.isEmpty {
                    Button {
                        cart.addAll(order.repeatableItems)
                        Haptics.play(.addedToCart)
                        router.selectedTab = .cart
                    } label: {
                        Label("Повторить заказ", systemImage: "arrow.clockwise")
                    }
                }
                if order.canCancel == true || (order.canCancel == nil && order.status == .processing) {
                    Button(role: .destructive) {
                        isCancelConfirming = true
                    } label: {
                        if viewModel.isCancelling { ProgressView() } else { Label("Отменить заявку", systemImage: "xmark.circle") }
                    }
                    .disabled(viewModel.isCancelling)
                }
                if let error = viewModel.actionError {
                    Text(error).font(.aaCaption).foregroundStyle(Palette.error)
                }
            }

            Section {
                ContactButtonsRow()
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } header: {
                Text("Вопрос по заказу")
            }
        }
        .listStyle(.insetGrouped)
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

private struct OrderLineRow: View {
    let line: OrderLine

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: line.image?.resolvedURL, contentMode: .fit, maxPixel: 200)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(line.productName ?? "")
                    .font(BrandFont.golos(14, .medium))
                    .foregroundStyle(Palette.textStrong)
                let details = [line.complectTitle, line.subTitle, line.timeLabel].compactMap { $0 }.joined(separator: " · ")
                if !details.isEmpty {
                    Text(details).font(.aaCaption).foregroundStyle(Palette.textSecondary)
                }
                if let qty = line.qty {
                    Text(verbatim: "× \(qty) \(line.qtyUnit ?? "")").font(.aaCaption).foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            if line.onRequest == true {
                Text("по запросу").font(.aaCaption)
            } else if let total = line.total {
                Text(Money.rub(total)).font(.aaCartItemPrice)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Таймлайн статусов: пройденные — из истории, будущие — серым.
private struct StatusTimeline: View {
    let order: Order

    private struct Step: Identifiable {
        let id: String
        let status: OrderStatus
        let title: String
        let date: Date?
        let comment: String?
        let isDone: Bool
    }

    private var steps: [Step] {
        var result: [Step] = order.history.enumerated().map { index, event in
            let status = event.status ?? .unknown
            return Step(id: "h\(index)", status: status, title: status != .unknown ? status.title : (event.label ?? status.title), date: event.at, comment: event.comment, isDone: true)
        }
        if order.status != .cancelled, order.status != .completed {
            let passed = Set(result.map(\.status))
            let currentIndex = OrderStatus.timeline.firstIndex(of: order.status) ?? 0
            for status in OrderStatus.timeline.dropFirst(currentIndex + 1) where !passed.contains(status) {
                result.append(Step(id: "f\(status.rawValue)", status: status, title: status.title, date: nil, comment: nil, isDone: false))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let all = steps
            ForEach(Array(all.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(step.isDone ? OrderStatusStyle.color(step.status) : Palette.bgTertiary)
                            .frame(width: 12, height: 12)
                            .padding(.top, 4)
                        if index < all.count - 1 {
                            Rectangle()
                                .fill(step.isDone ? OrderStatusStyle.color(step.status).opacity(0.4) : Palette.bgTertiary)
                                .frame(width: 2)
                                .frame(minHeight: 28)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(BrandFont.golos(15, step.isDone ? .semibold : .regular))
                            .foregroundStyle(step.isDone ? Palette.textProduct : Palette.textTertiary)
                        if let date = step.date {
                            Text(DateText.dateTime(date)).font(.aaCaption).foregroundStyle(Palette.textSecondary)
                        }
                        if let comment = step.comment, !comment.isEmpty {
                            Text(comment).font(.aaCaption).foregroundStyle(Palette.text)
                        }
                    }
                    .padding(.bottom, 12)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }
}
