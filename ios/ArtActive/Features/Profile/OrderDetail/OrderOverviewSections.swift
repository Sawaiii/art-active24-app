import SwiftUI

/// Раздел «Обзор» карточки заказа: машина на карте («В пути»), таймлайн, отзыв, претензия,
/// позиции с итогом, комментарий, действия, связь и тихая ссылка «Что-то пошло не так?».
struct OrderOverviewSections: View {
    let order: Order
    let orders: OrdersStore
    let isCancelling: Bool
    let actionError: String?
    let onCancel: () -> Void
    let onReview: (Int) -> Void
    let onClaim: () -> Void

    @Environment(CartStore.self) private var cart
    @Environment(Router.self) private var router

    init(
        order: Order,
        orders: OrdersStore,
        isCancelling: Bool,
        actionError: String?,
        onCancel: @escaping () -> Void,
        onReview: @escaping (Int) -> Void,
        onClaim: @escaping () -> Void
    ) {
        self.order = order
        self.orders = orders
        self.isCancelling = isCancelling
        self.actionError = actionError
        self.onCancel = onCancel
        self.onReview = onReview
        self.onClaim = onClaim
    }

    var body: some View {
        liveSections
        Section {
            StatusTimeline(order: order)
        } header: {
            Text("Статус")
        }
        feedbackSections
        linesSection
        commentSection
        actionsSection
        Section {
            ContactButtonsRow()
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } header: {
            Text("Вопрос по заказу")
        }
        claimLinkSection
    }

    @ViewBuilder
    private var liveSections: some View {
        if order.isTracking {
            Section {
                VehicleMapCard(orderId: order.id, orders: orders)
            } header: {
                Text("Машина с заказом")
            }
        }
    }

    @ViewBuilder
    private var feedbackSections: some View {
        if order.canReview == true || order.review != nil {
            Section {
                OrderReviewCard(review: order.review, canReview: order.canReview == true, onCompose: onReview)
            } header: {
                Text("Отзыв")
            }
        }
        if let claims = order.claims, !claims.isEmpty {
            Section {
                ForEach(claims) { claim in
                    ClaimStatusCard(claim: claim)
                }
            } header: {
                Text("Претензия")
            }
        }
    }

    @ViewBuilder
    private var linesSection: some View {
        if !order.lines.isEmpty {
            Section {
                ForEach(Array(order.lines.enumerated()), id: \.offset) { _, line in
                    OrderLineRow(line: line)
                }
                if let discount = order.discount {
                    DiscountSummaryRows(subtotal: order.subtotal ?? order.total + discount.amount, discount: discount)
                }
                HStack {
                    Text("Итого").font(BrandFont.golos(17, .semibold))
                    Spacer()
                    Text(Money.rub(order.total)).font(.aaCartTotal)
                }
                .accessibilityElement(children: .combine)
                if order.hasOnRequest == true {
                    Text("Часть позиций — по запросу.").font(.aaCaption).foregroundStyle(Palette.textSecondary)
                }
            } header: {
                Text("Позиции заказа")
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
    }

    @ViewBuilder
    private var commentSection: some View {
        if let comment = order.comment, !comment.isEmpty {
            Section {
                Text(comment)
            } header: {
                Text("Комментарий")
            }
        }
    }

    private var actionsSection: some View {
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
                    onCancel()
                } label: {
                    if isCancelling { ProgressView() } else { Label("Отменить заявку", systemImage: "xmark.circle") }
                }
                .accessibilityLabel(Text("Отменить заявку"))
                .disabled(isCancelling)
            }
            if let error = actionError {
                Label(error, systemImage: "exclamationmark.circle.fill").font(.aaCaption).foregroundStyle(Palette.error)
            }
        }
    }

    /// Претензия — не на виду: тихая ссылка в самом низу (и пункт в меню «…»).
    @ViewBuilder
    private var claimLinkSection: some View {
        if order.canClaim == true {
            Section {
                Button {
                    Haptics.play(.selection)
                    onClaim()
                } label: {
                    Text("Что-то пошло не так?")
                }
                .buttonStyle(LinkButtonStyle(font: .aaCaption))
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("orderDetail.claimLink")
            }
            .listRowBackground(Color.clear)
        }
    }
}

// MARK: - Скидка в итогах

/// Цвет суммы скидки: системный зелёный с контрастом ≥ 4.5:1 на белом (у Palette.success ~2:1 для текста).
enum DiscountStyle {
    static let amountColor = Color(light: 0x1E7D34, dark: 0x30D158)

    static func minus(_ amount: Int) -> String { "−" + Money.rub(amount) }
}

/// «Сумма» и строка скидки («Скидка постоянного клиента −5%» … −1 540 ₽) перед итогом —
/// корзина, оформление, заказ.
struct DiscountSummaryRows: View {
    let subtotal: Int
    let discount: PriceDiscount

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Сумма").foregroundStyle(Palette.textSecondary)
                Spacer()
                Text(Money.rub(subtotal)).foregroundStyle(Palette.textStrong)
            }
            .accessibilityElement(children: .combine)
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(discount.title)
                } icon: {
                    Image(systemName: "tag.fill")
                }
                .labelStyle(DiscountLabelStyle())
                .foregroundStyle(Palette.textStrong)
                Spacer(minLength: 8)
                Text(verbatim: DiscountStyle.minus(discount.amount))
                    .font(BrandFont.golos(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(DiscountStyle.amountColor)
            }
            .accessibilityElement(children: .combine)
        }
        .font(.aaBodySmall)
    }
}

/// Иконка и текст вплотную (у Label в строке List широкая колонка под иконку).
private struct DiscountLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            configuration.title
        }
    }
}
