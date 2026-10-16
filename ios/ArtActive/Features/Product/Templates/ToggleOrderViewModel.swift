import Foundation
import Observation

/// Шаблоны 88/81 (`orderMode = toggle`): комплект и каждая опция кладутся в корзину
/// своим переключателем (как кнопки add-cart на сайте), без количества и времени.
/// Опция — «строка-опция» без `complectId` (цена = Σ допов × qty).
@MainActor
@Observable
final class ToggleOrderViewModel {
    let product: Product

    @ObservationIgnored private let cart: CartStore

    init(product: Product, cart: CartStore) {
        self.product = product
        self.cart = cart
    }

    // MARK: - Комплекты

    func key(_ complect: Complect) -> CartLineKey {
        complectInput(complect).lineKey
    }

    func isInCart(_ complect: Complect) -> Bool { cart.contains(key(complect)) }

    func toggle(_ complect: Complect) {
        if isInCart(complect) {
            cart.remove(key(complect))
            Haptics.play(.selection)
        } else {
            cart.add(complectInput(complect))
            Haptics.play(.addedToCart)
        }
    }

    // MARK: - Опции

    func isInCart(extra id: String) -> Bool {
        cart.contains(CartItemInput.option(productId: product.id, extraIds: [id]).lineKey)
    }

    func toggleOption(_ id: String) {
        let input = CartItemInput.option(productId: product.id, extraIds: [id])
        if cart.contains(input.lineKey) {
            cart.remove(input.lineKey)
            Haptics.play(.selection)
        } else {
            cart.add(input)
            Haptics.play(.addedToCart)
        }
    }

    /// Обязательные допы отдельной позицией не продаются — их показываем справочно.
    var options: [Extra] { product.extras.filter { !$0.isRequired } }

    var extraGroups: [String] {
        var groups: [String] = []
        for extra in options {
            let group = extra.group ?? ""
            if !groups.contains(group) { groups.append(group) }
        }
        return groups
    }

    func extras(in group: String?) -> [Extra] {
        guard let group else { return options }
        return options.filter { ($0.group ?? "") == group }
    }

    // MARK: - Тексты

    /// «доп. час — X ₽» для комплекта с правилом времени (шаблон 81 — текстом, без калькулятора).
    func hint(for complect: Complect) -> String? {
        guard let rule = complect.time, let side = complect.rent, rule.percent > 0 else { return nil }
        let step = Pricing.roundRub(Double(side.amount) * rule.percent / 100)
        guard step > 0 else { return nil }
        return rule.unit == .hours
            ? String(localized: "доп. час — \(Money.rub(step))")
            : String(localized: "доп. день — \(Money.rub(step))")
    }

    /// «от 26 000 ₽ / 6 ч»
    func priceText(for complect: Complect) -> String {
        guard let side = complect.rent ?? complect.buy else { return "" }
        var text = ComplectPrice.text(complect, priceType: complect.rent == nil ? .buy : .rent)
        if let rule = complect.time, side.postfix == nil, side.onRequest != true {
            text += " / " + (rule.unit == .hours ? String(localized: "\(rule.defaultValue) ч") : String(localized: "\(rule.defaultValue) д"))
        }
        return text
    }

    private func complectInput(_ complect: Complect) -> CartItemInput {
        CartItemInput(
            productId: product.id,
            complectId: complect.id,
            priceType: complect.rent == nil && complect.buy != nil ? .buy : .rent,
            qty: 1
        )
    }
}
