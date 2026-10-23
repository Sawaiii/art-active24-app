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
        // HStack, а не Label: внутри List у Label фиксированная колонка под иконку,
        // из-за чего между символом и словом появлялся пустой разрыв ~20 pt.
        HStack(spacing: 5) {
            Image(systemName: OrderStatusStyle.symbol(status))
                .foregroundStyle(OrderStatusStyle.color(status))
                .accessibilityHidden(true)
            // Локальная подпись по статусу; серверная — только для неизвестного статуса.
            Text(status != .unknown || label.isEmpty ? status.title : label)
                .lineLimit(1)
        }
        .font(BrandFont.golos(12, .semibold, relativeTo: .caption))
        // Текст — нейтральным цветом (контраст ≥ 4.5:1); цвет несут только иконка и подложка,
        // статус читается по слову и символу, а не по цвету.
        .foregroundStyle(Palette.textStrong)
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
                .accessibilityIdentifier("order.\(order.id)")
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
                        .accessibilityIdentifier("order.unseenDot")
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

// Детали заказа — OrderDetail/OrderDetailView.swift.

struct OrderLineRow: View {
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
struct StatusTimeline: View {
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
                        Group {
                            if step.isDone {
                                Circle().fill(OrderStatusStyle.color(step.status))
                            } else {
                                Circle().strokeBorder(Palette.textTertiary, lineWidth: 1.5)
                            }
                        }
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
                            // Комментарий менеджера — главное сообщение шага; не обрезаем «…».
                            Text(comment)
                                .font(.aaCaption)
                                .foregroundStyle(Palette.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 12)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(step.isDone ? Text("Пройден") : Text("Ожидается"))
            }
        }
        .padding(.vertical, 4)
    }
}
