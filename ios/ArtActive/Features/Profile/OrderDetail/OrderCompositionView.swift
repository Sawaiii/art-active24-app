import SwiftUI

/// Раздел «Состав»: состав заказа из «Программы КП» (или от менеджера / по позициям заявки)
/// по разделам — Мебель, Кейтеринг, Персонал, Логистика; итоги со скидками и доставкой.
struct OrderCompositionSections: View {
    let order: Order
    let state: ViewState<OrderComposition>
    let retry: () async -> Void

    /// Свёрнутые разделы (по умолчанию всё раскрыто).
    @State private var collapsed: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(order: Order, state: ViewState<OrderComposition>, retry: @escaping () async -> Void) {
        self.order = order
        self.state = state
        self.retry = retry
    }

    var body: some View {
        switch state {
        case .loading:
            Section {
                ListSkeleton(rows: 4)
                    .padding(.vertical, 8)
            }
        case let .error(message):
            Section {
                ErrorStateView(message: message, retry: retry)
            }
        case .empty:
            Section {
                EmptyStateView(
                    systemImage: "list.bullet.rectangle",
                    title: String(localized: "Состав появится, когда менеджер подготовит предложение"),
                    message: String(localized: "Мы пришлём уведомление, а здесь будут все позиции с ценами.")
                )
            }
        case let .content(composition):
            content(composition)
        }
    }

    @ViewBuilder
    private func content(_ composition: OrderComposition) -> some View {
        Section {
            CompositionMetaRow(composition: composition)
        }
        ForEach(composition.sections) { section in
            Section {
                if !collapsed.contains(section.id) {
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        CompositionLineRow(line: line)
                    }
                }
            } header: {
                sectionHeader(section)
            }
        }
        Section {
            CompositionTotals(composition: composition)
            ShareLink(item: CompositionShareText.make(composition, orderNumber: order.number)) {
                Label("Поделиться составом", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("orderDetail.compositionShare")
        } header: {
            Text("Итого")
        } footer: {
            if let vat = composition.vatNote, !vat.isEmpty {
                Text(vat)
            }
        }
    }

    private func sectionHeader(_ section: CompositionSection) -> some View {
        let isCollapsed = collapsed.contains(section.id)
        return Button {
            Haptics.play(.selection)
            withAnimation(Motion.snappy(reduceMotion)) {
                if isCollapsed { collapsed.remove(section.id) } else { collapsed.insert(section.id) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(section.title)
                    .font(BrandFont.golos(15, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.textProduct)
                Spacer(minLength: 8)
                Text(Money.rub(section.subtotal))
                    .font(BrandFont.golos(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textStrong)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityValue(isCollapsed ? Text("Свёрнуто") : Text("Развёрнуто"))
        .accessibilityHint(Text("Показать или скрыть позиции раздела"))
        .accessibilityIdentifier("orderDetail.composition.section.\(section.id)")
    }
}

/// Номер и дата КП, версия, когда обновлено.
private struct CompositionMetaRow: View {
    let composition: OrderComposition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: sourceSymbol)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(sourceTitle)
                    .font(BrandFont.golos(15, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.textProduct)
            }
            if let kpNumber = composition.kpNumber {
                let kpDate = DateText.day(fromAPI: composition.kpDate)
                Text(kpDate.map { date in String(localized: "КП \(kpNumber) от \(date)") } ?? String(localized: "КП \(kpNumber)"))
                    .font(.aaBodySmall)
                    .foregroundStyle(Palette.text)
            }
            HStack(spacing: 4) {
                let versionValue = composition.version
                Text("Версия \(versionValue)")
                if let updatedAt = composition.updatedAt {
                    Text(verbatim: "·")
                    Text("обновлено")
                    Text(updatedAt, format: .relative(presentation: .named))
                }
            }
            .font(.aaCaption)
            .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var sourceTitle: String {
        switch composition.source {
        case .kp: return String(localized: "Коммерческое предложение")
        case .manager: return String(localized: "Состав от менеджера")
        case .cart, .empty, .unknown: return String(localized: "По позициям заявки")
        }
    }

    private var sourceSymbol: String {
        switch composition.source {
        case .kp: return "list.bullet.rectangle"
        case .manager: return "person.crop.circle.badge.checkmark"
        case .cart, .empty, .unknown: return "cart"
        }
    }
}

/// Строка состава: название, артикул, количество × цена, срок, примечание, сумма.
private struct CompositionLineRow: View {
    let line: CompositionLine

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.name)
                    .font(BrandFont.golos(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textStrong)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if line.onRequest == true {
                    Text("по запросу").font(.aaCartItemPrice).foregroundStyle(Palette.textStrong)
                } else {
                    Text(Money.rub(line.sum)).font(.aaCartItemPrice).foregroundStyle(Palette.textStrong)
                }
            }
            HStack(spacing: 6) {
                if let art = line.art, !art.isEmpty {
                    Text(verbatim: art)
                        .font(BrandFont.golos(11, .medium, relativeTo: .caption2))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: Radius.xs).fill(Palette.chipArticle))
                }
                Text(verbatim: CompositionShareText.quantity(line))
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let note = line.note, !note.isEmpty {
                Text(note)
                    .font(.aaCaption)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Итоги состава: сумма, скидки, доставка, к оплате.
private struct CompositionTotals: View {
    let composition: OrderComposition

    var body: some View {
        VStack(spacing: 8) {
            row(String(localized: "Сумма"), Money.rub(composition.subtotal))
            ForEach(Array((composition.discounts ?? []).enumerated()), id: \.offset) { _, discount in
                HStack(alignment: .firstTextBaseline) {
                    Text(discount.title).foregroundStyle(Palette.textStrong)
                    Spacer(minLength: 8)
                    Text(verbatim: DiscountStyle.minus(discount.amount))
                        .font(BrandFont.golos(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(DiscountStyle.amountColor)
                }
                .accessibilityElement(children: .combine)
            }
            if let delivery = composition.delivery {
                row(String(localized: "Доставка"), Money.rub(delivery))
            } else {
                row(String(localized: "Доставка"), String(localized: "рассчитает менеджер"))
            }
            if let note = composition.deliveryNote, !note.isEmpty {
                Text(note)
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("К оплате").font(BrandFont.golos(17, .semibold))
                Spacer()
                Text(Money.rub(composition.total)).font(.aaCartTotal)
            }
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
            if composition.hasOnRequest == true {
                Text("Часть позиций — по запросу.")
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.aaBodySmall)
        .padding(.vertical, 4)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 8)
            Text(value).foregroundStyle(Palette.textStrong)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Текст для «Поделиться»

enum CompositionShareText {
    /// «10 шт × 924 ₽ · 2 д»
    static func quantity(_ line: CompositionLine) -> String {
        let qty = line.qty.formatted(.number.precision(.fractionLength(0...2)))
        var text = "\(qty) \(line.unit)"
        if line.onRequest != true {
            text += " × \(Money.rub(line.price))"
        }
        if let daysCount = line.days {
            text += " · " + String(localized: "\(daysCount) д")
        }
        return text
    }

    static func make(_ composition: OrderComposition, orderNumber: String) -> String {
        var out: [String] = [String(localized: "Состав заказа \(orderNumber)")]
        if let kpNumber = composition.kpNumber {
            out.append(String(localized: "КП \(kpNumber)") + (DateText.day(fromAPI: composition.kpDate).map { " · \($0)" } ?? ""))
        }
        for section in composition.sections {
            out.append("")
            out.append("\(section.title) — \(Money.rub(section.subtotal))")
            for line in section.lines {
                let sum = line.onRequest == true ? String(localized: "по запросу") : Money.rub(line.sum)
                out.append("• \(line.name): \(quantity(line)) = \(sum)")
            }
        }
        out.append("")
        out.append("\(String(localized: "Сумма")): \(Money.rub(composition.subtotal))")
        for discount in composition.discounts ?? [] {
            out.append("\(discount.title): \(DiscountStyle.minus(discount.amount))")
        }
        let delivery = composition.delivery.map { Money.rub($0) } ?? String(localized: "рассчитает менеджер")
        out.append("\(String(localized: "Доставка")): \(delivery)")
        out.append("\(String(localized: "К оплате")): \(Money.rub(composition.total))")
        if let vat = composition.vatNote, !vat.isEmpty { out.append(vat) }
        return out.joined(separator: "\n")
    }

    /// Состав не загружен — позиции заказа.
    static func make(order: Order) -> String? {
        guard !order.lines.isEmpty else { return nil }
        var out: [String] = [String(localized: "Состав заказа \(order.number)")]
        for line in order.lines {
            let details = [line.complectTitle, line.timeLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            let sum = line.onRequest == true ? String(localized: "по запросу") : Money.rub(line.total ?? 0)
            let qty = line.qty.map { " × \($0) \(line.qtyUnit ?? "")" } ?? ""
            out.append("• \(line.productName ?? "")\(details.isEmpty ? "" : " (\(details))")\(qty) = \(sum)")
        }
        if let discount = order.discount {
            out.append("\(discount.title): \(DiscountStyle.minus(discount.amount))")
        }
        out.append("\(String(localized: "Итого")): \(Money.rub(order.total))")
        return out.joined(separator: "\n")
    }
}
