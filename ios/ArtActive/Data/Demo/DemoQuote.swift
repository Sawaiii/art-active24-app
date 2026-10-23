import CryptoKit
import Foundation

/// Позиции корзины и серверный расчёт (CartItem.php + QuoteService.php + метаданные PriceCalculator.php).
/// Цены считает `Pricing` — та же формула, что на сервере (общие векторы contract/pricing-vectors.json).
struct DemoQuoteService: Sendable {
    let data: DemoDataset

    static let maxItems = 100
    static let maxQty = 10_000
    static let maxTime = 365

    // MARK: - Разбор позиций

    /// `items` из тела запроса → провалидированные позиции (ошибки полей «items.N.поле»).
    func items(from json: Any?, allowEmpty: Bool = true) throws -> [CartItemInput] {
        guard let raw = json as? [Any], raw.count <= Self.maxItems else {
            throw DemoError.validation(["items": "Ожидается список до \(Self.maxItems) позиций"])
        }
        if raw.isEmpty, !allowEmpty {
            throw DemoError.validation(["items": "Корзина пуста"])
        }
        let decoder = JSONCoding.makeDecoder()
        var items: [CartItemInput] = []
        var errors: [String: String] = [:]
        for (index, element) in raw.enumerated() {
            let prefix = "items.\(index)."
            guard JSONSerialization.isValidJSONObject(element),
                  let data = try? JSONSerialization.data(withJSONObject: element),
                  let item = try? decoder.decode(CartItemInput.self, from: data) else {
                errors[prefix + "productId"] = "Укажите товар"
                continue
            }
            if item.productId <= 0 { errors[prefix + "productId"] = "Укажите товар" }
            if let complectId = item.complectId, complectId <= 0 { errors[prefix + "complectId"] = "Некорректный комплект" }
            if item.qty < 1 || item.qty > Self.maxQty {
                errors[prefix + "qty"] = "Количество должно быть от 1 до \(Self.maxQty)"
            }
            if item.priceType == .unknown { errors[prefix + "priceType"] = "Тип цены: аренда или покупка" }
            if let time = item.time, time.unit == .unknown || time.value < 1 || time.value > Self.maxTime {
                errors[prefix + "time"] = "Некорректное время аренды"
            }
            if item.complectId == nil, (item.extras ?? []).isEmpty {
                errors[prefix + "complectId"] = "Выберите комплект или дополнительную опцию"
            }
            items.append(normalized(item))
        }
        if !errors.isEmpty { throw DemoError.validation(errors) }
        return items
    }

    /// Как `CartItem::toArray`: тип цены всегда указан, одинаковые допы/строки меню схлопнуты.
    func normalized(_ item: CartItemInput) -> CartItemInput {
        var extras: [(String, Int)] = []
        for extra in item.extras ?? [] {
            if let index = extras.firstIndex(where: { $0.0 == extra.id }) {
                extras[index].1 += extra.qty ?? 1
            } else {
                extras.append((extra.id, extra.qty ?? 1))
            }
        }
        var menu: [(String, Int)] = []
        for row in item.menu ?? [] {
            if let index = menu.firstIndex(where: { $0.0 == row.id }) {
                menu[index].1 += row.qty
            } else {
                menu.append((row.id, row.qty))
            }
        }
        return CartItemInput(
            productId: item.productId,
            complectId: item.complectId,
            subId: item.subId,
            priceType: item.priceType ?? .rent,
            time: item.time,
            qty: item.qty,
            extras: extras.isEmpty ? nil : extras.map { ExtraSelection(id: $0.0, qty: $0.1) },
            menu: menu.isEmpty ? nil : menu.map { MenuSelection(id: $0.0, qty: $0.1) }
        )
    }

    /// Ключ конфигурации (без количества): одинаковые настройки — одна строка корзины.
    func key(_ item: CartItemInput) -> String {
        let extras = (item.extras ?? []).map { "\($0.id)=\($0.qty ?? 1)" }.sorted().joined(separator: ",")
        let menu = (item.menu ?? []).map { "\($0.id)=\($0.qty)" }.sorted().joined(separator: ",")
        let parts = [
            String(item.productId), item.complectId.map(String.init) ?? "-", item.subId ?? "-",
            (item.priceType ?? .rent).rawValue, item.time?.unit.rawValue ?? "-", item.time.map { String($0.value) } ?? "-",
            extras, menu,
        ]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// PUT /v1/cart: одинаковые конфигурации схлопываются с суммой количеств.
    func merged(_ items: [CartItemInput]) -> [CartItemInput] {
        var order: [String] = []
        var byKey: [String: CartItemInput] = [:]
        for item in items {
            let itemKey = key(item)
            if var existing = byKey[itemKey] {
                existing.qty = min(Self.maxQty, existing.qty + item.qty)
                byKey[itemKey] = existing
            } else {
                order.append(itemKey)
                byKey[itemKey] = item
            }
        }
        return order.compactMap { byKey[$0] }
    }

    // MARK: - Расчёт

    func quote(_ items: [CartItemInput]) -> Quote {
        let lines = items.map { line($0, product: data.product($0.productId)) }
        let available = lines.filter(\.available)
        return Quote(
            lines: lines,
            total: available.reduce(0) { $0 + $1.total },
            hasOnRequest: available.contains { $0.onRequest == true },
            count: lines.count
        )
    }

    private func line(_ item: CartItemInput, product: Product?) -> QuoteLine {
        let base = LineDraft(item: item, key: key(item), product: product)
        guard let product else { return base.unavailable("Товар снят с продажи") }
        if product.orderMode == .request { return base.unavailable("Этот товар заказывается через заявку") }
        if item.complectId == nil, product.orderMode != .toggle { return base.unavailable("Выберите комплект") }

        let selected = item.extras ?? []
        if selected.contains(where: { selection in !product.extras.contains { $0.id == selection.id } }) {
            return base.unavailable("Дополнительная опция не найдена")
        }

        // Строка-опция (simple/showcase): сумма выбранных допов × количество.
        guard let complectId = item.complectId else {
            do {
                let price = try Pricing.optionLine(extras: product.extras, selected: selected, qty: item.qty)
                let names = selected.compactMap { selection in product.extras.first { $0.id == selection.id }?.name }
                return base.priced(
                    complectTitle: names.joined(separator: ", "), subTitle: nil, priceLabel: "Опция", timeLabel: nil,
                    qtyUnit: "шт", extras: [], unitPrice: price.unitPrice, total: price.total, onRequest: false
                )
            } catch {
                return base.unavailable(Self.reason(error))
            }
        }

        guard let complect = product.complects.first(where: { $0.id == complectId }) else {
            return base.unavailable("Комплект больше недоступен")
        }
        let priceType = item.priceType ?? .rent
        let isMenu = !complect.menuRows.isEmpty
        if !isMenu, complect.side(priceType) == nil {
            return base.unavailable(priceType == .buy ? "Этот комплект нельзя купить" : "Этот комплект нельзя арендовать", complectTitle: complect.title)
        }
        if item.subId != nil, complect.subList.isEmpty {
            return base.unavailable("У комплекта нет вариантов", complectTitle: complect.title)
        }

        let input = PricingInput(
            priceType: priceType,
            subId: item.subId,
            time: item.time,
            qty: item.qty,
            extras: selected,
            menu: item.menu ?? []
        )
        let price: PriceResult
        do {
            price = try Pricing.calculate(complect: complect, extras: product.extras, input: input)
        } catch {
            return base.unavailable(Self.reason(error), complectTitle: complect.title)
        }

        let sub = item.subId.flatMap { id in complect.subList.first { $0.id == id } }
        let side = complect.side(priceType)
        let subSide = sub?.side(priceType)
        return base.priced(
            complectTitle: complect.title,
            subTitle: sub?.name,
            priceLabel: isMenu ? (complect.rent?.label ?? "Стоимость") : (side?.label ?? ""),
            timeLabel: price.timeLabel,
            qtyUnit: isMenu ? "набор" : Self.qtyUnit(subSide?.postfix ?? side?.postfix ?? ""),
            extras: Self.extraLines(product.extras, selected: selected),
            unitPrice: price.unitPrice,
            total: price.total,
            onRequest: price.onRequest
        )
    }

    /// Допы позиции: выбранные + обязательные (входят всегда), несчётные — по 1 шт.
    static func extraLines(_ extras: [Extra], selected: [ExtraSelection]) -> [QuoteLineExtra] {
        var lines: [QuoteLineExtra] = []
        var used = Set<String>()
        for selection in selected {
            guard let extra = extras.first(where: { $0.id == selection.id }) else { continue }
            used.insert(extra.id)
            lines.append(QuoteLineExtra(name: extra.name, qty: extra.isCountable ? (selection.qty ?? 1) : 1, price: extra.price))
        }
        for extra in extras where extra.isRequired && !used.contains(extra.id) {
            lines.append(QuoteLineExtra(name: extra.name, qty: 1, price: extra.price))
        }
        return lines
    }

    /// Единица количества из постфикса: «/ порц.» → «порц.»; «/ до 40 чел» (вместимость) → «шт».
    static func qtyUnit(_ postfix: String) -> String {
        var text = postfix.replacingOccurrences(of: "/", with: " ")
        text = text.filter { !$0.isNumber }
        let words = text.split(separator: " ").map(String.init).filter { $0 != "за" }
        let unit = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if unit.isEmpty || unit == "до" || unit.hasPrefix("до ") { return "шт" }
        return unit
    }

    private static func reason(_ error: Error) -> String {
        (error as? PricingError)?.message ?? "Позицию нельзя рассчитать"
    }
}

/// Черновик строки quote — общие поля строки, доступной и недоступной.
private struct LineDraft {
    let item: CartItemInput
    let key: String
    let product: Product?

    func unavailable(_ warning: String, complectTitle: String = "") -> QuoteLine {
        make(complectTitle: complectTitle, subTitle: nil, priceLabel: nil, timeLabel: nil, qtyUnit: "шт", extras: [],
             unitPrice: 0, total: 0, onRequest: false, available: false, warning: warning)
    }

    func priced(
        complectTitle: String, subTitle: String?, priceLabel: String, timeLabel: String?, qtyUnit: String,
        extras: [QuoteLineExtra], unitPrice: Int, total: Int, onRequest: Bool
    ) -> QuoteLine {
        make(complectTitle: complectTitle, subTitle: subTitle, priceLabel: priceLabel, timeLabel: timeLabel, qtyUnit: qtyUnit,
             extras: extras, unitPrice: unitPrice, total: total, onRequest: onRequest, available: true, warning: nil)
    }

    private func make(
        complectTitle: String, subTitle: String?, priceLabel: String?, timeLabel: String?, qtyUnit: String,
        extras: [QuoteLineExtra], unitPrice: Int, total: Int, onRequest: Bool, available: Bool, warning: String?
    ) -> QuoteLine {
        QuoteLine(
            key: key,
            input: item,
            productName: product?.name ?? "Товар недоступен",
            productSlug: product?.slug,
            image: product?.media.first?.url,
            art: product?.art,
            complectTitle: complectTitle,
            subTitle: subTitle,
            priceLabel: priceLabel,
            timeLabel: timeLabel,
            qtyUnit: qtyUnit,
            extras: extras,
            unitPrice: unitPrice,
            total: total,
            onRequest: onRequest,
            available: available,
            warning: warning
        )
    }
}
