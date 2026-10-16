import Foundation
import Observation

/// Состояние конфигуратора карточки и связь с корзиной. Вся логика выбора и цены —
/// в доменном `Configurator`; здесь только хранение, хаптики и синхронизация корзины.
@MainActor
@Observable
final class ConfiguratorViewModel {
    let configurator: Configurator
    private(set) var state: ConfiguratorState?
    /// Растёт при добавлении в корзину — триггер анимации «полёт в таб».
    private(set) var flyPulse = 0

    @ObservationIgnored private let cart: CartStore

    init(product: Product, preselect: ProductPreselection?, cart: CartStore) {
        let configurator = Configurator(product: product)
        self.configurator = configurator
        self.cart = cart
        var initial = configurator.initialState(preselect: preselect)
        // Позиция уже в корзине — восстанавливаем её конфигурацию.
        if let current = initial,
           let existing = cart.item(for: configurator.cartInput(current).lineKey),
           let restored = configurator.state(from: existing) {
            initial = restored
        }
        state = initial
    }

    var product: Product { configurator.product }
    var mode: ConfiguratorMode { configurator.mode }

    // MARK: - Derived

    var complect: Complect? { state.flatMap { configurator.complect($0) } }
    var price: PriceResult? { state.flatMap { configurator.price($0) } }
    var validationError: PricingError? { state.flatMap { configurator.validationError($0) } }

    var cartLine: CartItemInput? {
        guard let state else { return nil }
        return cart.item(for: configurator.cartInput(state).lineKey)
    }

    var isInCart: Bool { cartLine != nil }

    var priceLabel: String { state.map { configurator.priceLabel($0) } ?? "" }
    var badge: String? { state.flatMap { configurator.badge($0) } }
    var hint: String? { state.flatMap { configurator.hint($0) } }
    var postfix: String? { state.flatMap { configurator.postfix($0) } }
    var showsFrom: Bool { state.map { configurator.showsFrom($0) } ?? false }
    var qtyUnit: String { state.map { configurator.qtyUnit($0) } ?? "" }
    var minQty: Int { state.map { configurator.minQty($0) } ?? 1 }
    var breakdown: [BreakdownSection] { state.map { configurator.breakdown($0) } ?? [] }
    var subGroups: [SubGroup] { state.map { configurator.subGroups($0) } ?? [] }
    var timeOptions: TimeOptions? { state.flatMap { configurator.timeOptions($0) } }
    var priceTypes: [PriceType] { complect.map { configurator.availablePriceTypes($0) } ?? [] }
    var menuGroups: [MenuGroup] { state.map { configurator.menuGroups($0) } ?? [] }
    var shareURL: URL? { state.flatMap { configurator.shareURL($0) } }

    /// Цена в баре: для меню — итог, иначе цена за единицу.
    var barAmount: Int? {
        guard let price, !price.onRequest else { return nil }
        return mode == .cateringMenu ? price.total : price.unitPrice
    }

    var rewardProgress: Double? {
        guard mode == .cateringMenu, let complect, let price else { return nil }
        return Pricing.rewardProgress(complect.reward, menuSum: price.unitPrice)
    }

    func isSelected(extra id: String) -> Bool { (state?.extras[id] ?? 0) > 0 }
    func extraQty(_ id: String) -> Int { state?.extras[id] ?? 0 }
    func menuQty(_ id: String) -> Int { state?.menu[id] ?? 0 }

    // MARK: - Actions

    func selectComplect(_ id: Int) {
        guard let state, state.complectId != id else { return }
        Haptics.play(.selection)
        self.state = configurator.selectingComplect(id, from: state)
    }

    func selectSub(_ id: String) {
        guard let state, state.subId != id else { return }
        Haptics.play(.selection)
        apply(configurator.selectingSub(id, from: state))
    }

    func selectPriceType(_ type: PriceType) {
        guard let state, state.priceType != type else { return }
        Haptics.play(.selection)
        self.state = configurator.selectingPriceType(type, from: state)
    }

    func selectTime(_ time: TimeSelection) {
        guard let state, state.time != time else { return }
        Haptics.play(.selection)
        apply(configurator.selectingTime(time, from: state))
    }

    func toggleExtra(_ id: String) {
        guard let state else { return }
        if product.extras.first(where: { $0.id == id })?.isRequired == true {
            Haptics.play(.limit)
            return
        }
        Haptics.play(.selection)
        apply(configurator.togglingExtra(id, from: state))
    }

    func setExtraQty(_ id: String, _ qty: Int) {
        guard let state else { return }
        apply(configurator.settingExtraQty(id, qty: qty, from: state))
    }

    func setMenuQty(_ id: String, _ qty: Int) {
        guard let state else { return }
        apply(configurator.settingMenuQty(id, qty: qty, from: state))
    }

    func addToCart() {
        guard let state else { return }
        if let error = configurator.validationError(state) {
            Haptics.play(.error)
            lastError = error.message
            return
        }
        let input = configurator.cartInput(state)
        cart.add(input)
        Haptics.play(.addedToCart)
        flyPulse += 1
    }

    /// Степпер в баре меняет количество позиции в корзине; «−» на минимуме — удалить.
    func setCartQty(_ qty: Int) {
        guard let state else { return }
        let next = configurator.settingQty(qty, from: state)
        self.state = next
        cart.setQty(next.qty, for: configurator.cartInput(next).lineKey)
    }

    func removeFromCart() {
        guard let state else { return }
        cart.remove(configurator.cartInput(state).lineKey)
        self.state = configurator.settingQty(configurator.minQty(state), from: state)
    }

    /// Последняя ошибка валидации для показа под баром.
    var lastError: String?

    /// Изменение выбора: если позиция уже в корзине — синхронизируем её конфигурацию.
    private func apply(_ next: ConfiguratorState) {
        let wasInCart = isInCart
        state = next
        lastError = nil
        guard wasInCart || isInCart, configurator.validationError(next) == nil else { return }
        if let line = cart.item(for: configurator.cartInput(next).lineKey) {
            var input = configurator.cartInput(next)
            input.qty = max(line.qty, configurator.minQty(next))
            cart.update(input)
        }
    }
}
