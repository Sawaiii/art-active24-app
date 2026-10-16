import Foundation

/// Логика конфигуратора карточки (шаблон 128) — повторяет поведение сайта
/// (`scripts-new26.js`, `mk2026.js`). Чистые функции над `ConfiguratorState`;
/// ViewModel только хранит состояние и вызывает эти методы.
struct Configurator: Sendable {
    let product: Product

    init(product: Product) {
        self.product = product
    }

    var mode: ConfiguratorMode {
        switch product.configuratorMode {
        case .trampoline?: return .trampoline
        case .cateringMenu?: return .cateringMenu
        case .masterclass?: return .masterclass
        default:
            // Меню у комплектов без явного режима — тоже кейтеринг.
            return product.complects.contains { !$0.menuRows.isEmpty } ? .cateringMenu : .standard
        }
    }

    // MARK: - Initial state

    func initialState(preselect: ProductPreselection? = nil) -> ConfiguratorState? {
        let preferred = preselect?.complectId.flatMap { id in product.complects.first { $0.id == id } }
        guard let complect = preferred ?? product.complects.first else { return nil }

        let types = availablePriceTypes(complect)
        let priceType = preselect?.priceType.flatMap { types.contains($0) ? $0 : nil } ?? types.first ?? .rent

        var state = ConfiguratorState(
            complectId: complect.id,
            subId: nil,
            priceType: priceType,
            time: complect.time.map { TimeSelection(unit: $0.unit, value: $0.defaultValue) },
            qty: 1,
            extras: requiredExtras(),
            menu: [:]
        )
        state.subId = defaultSubId(for: complect, priceType: priceType, preferred: preselect?.subId)
        state.menu = defaultMenu(for: complect)
        state.qty = minQty(state)
        return state
    }

    // MARK: - Lookup

    func complect(_ state: ConfiguratorState) -> Complect? {
        product.complects.first { $0.id == state.complectId }
    }

    func sub(_ state: ConfiguratorState) -> Sub? {
        guard let id = state.subId, let complect = complect(state) else { return nil }
        return complect.subList.first { $0.id == id }
    }

    /// Доступные стороны цены: аренда / покупка.
    func availablePriceTypes(_ complect: Complect) -> [PriceType] {
        var types: [PriceType] = []
        if complect.rent != nil || complect.subList.contains(where: { $0.rent != nil }) { types.append(.rent) }
        if complect.buy != nil || complect.subList.contains(where: { $0.buy != nil }) { types.append(.buy) }
        return types.isEmpty ? [.rent] : types
    }

    /// Батут: в «Купить» скрыты способ установки и время.
    func showsSubs(_ state: ConfiguratorState) -> Bool {
        guard mode != .cateringMenu, let complect = complect(state) else { return false }
        // Вариант выбирается (и уходит на сервер), только если у вариантов есть цена этой стороны:
        // покупка батута без цены buy у способов установки — без выбора варианта.
        return complect.subList.contains { $0.side(state.priceType) != nil }
    }

    func subGroups(_ state: ConfiguratorState) -> [SubGroup] {
        guard showsSubs(state), let complect = complect(state) else { return [] }
        let relevant = complect.subList.filter { $0.side(state.priceType) != nil }
        var groups: [SubGroup] = []
        for sub in relevant {
            if let index = groups.firstIndex(where: { $0.title == sub.group }) {
                let existing = groups[index]
                groups[index] = SubGroup(title: existing.title, subs: existing.subs + [sub])
            } else {
                groups.append(SubGroup(title: sub.group, subs: [sub]))
            }
        }
        return groups
    }

    func subsTitle(_ state: ConfiguratorState) -> String {
        if let label = complect(state)?.subsLabel, !label.isEmpty { return label }
        return mode == .trampoline ? String(localized: "Способ установки") : String(localized: "Варианты")
    }

    func complectsTitle() -> String {
        if mode == .masterclass, let label = product.masterclass?.variantsLabel, !label.isEmpty { return label }
        if let label = product.complectsLabel, !label.isEmpty { return label }
        return String(localized: "Комплекты")
    }

    /// Шаг выбора формата скрыт, если комплект один (батут с 1 комплектом).
    var showsComplectPicker: Bool { product.complects.count > 1 }

    // MARK: - Time

    /// Правило времени, если оно применяется к текущему выбору.
    func activeTimeRule(_ state: ConfiguratorState) -> TimeRule? {
        guard mode != .masterclass, mode != .cateringMenu,
              let complect = complect(state), let rule = complect.time, rule.unit != .unknown else { return nil }
        if mode == .trampoline, state.priceType == .buy { return nil }
        let sub = sub(state)
        if complect.side(state.priceType)?.sale == true || sub?.side(state.priceType)?.sale == true { return nil }
        return rule
    }

    func timeOptions(_ state: ConfiguratorState) -> TimeOptions? {
        guard let rule = activeTimeRule(state) else { return nil }
        let def = max(rule.defaultValue, 1)
        switch rule.unit {
        case .hours:
            let upper = max(Pricing.maxHours, def)
            let hours = (def...upper).map { TimeOption.value(TimeSelection(unit: .hours, value: $0)) }
            let days = (2...4).map { TimeOption.value(TimeSelection(unit: .days, value: $0)) } + [.more]
            return TimeOptions(rule: rule, primary: hours, days: days, moreMinimum: 5)
        case .days, .unknown:
            let days = (def...(def + 5)).map { TimeOption.value(TimeSelection(unit: .days, value: $0)) } + [.more]
            return TimeOptions(rule: rule, primary: days, days: [], moreMinimum: def + 6)
        }
    }

    func timeTitle(_ state: ConfiguratorState) -> String {
        guard let rule = activeTimeRule(state) else { return "" }
        return rule.unit == .days ? String(localized: "Время аренды (дней)") : String(localized: "Время аренды")
    }

    // MARK: - Price

    func pricingInput(_ state: ConfiguratorState) -> PricingInput {
        PricingInput(
            priceType: state.priceType,
            subId: showsSubs(state) ? state.subId : nil,
            time: activeTimeRule(state) == nil ? nil : state.time,
            qty: state.qty,
            extras: extraSelections(state),
            menu: menuSelections(state)
        )
    }

    /// Цена текущего выбора; nil — нет комплекта или выбор не проходит валидацию.
    func price(_ state: ConfiguratorState) -> PriceResult? {
        guard let complect = complect(state) else { return nil }
        return try? Pricing.calculate(complect: complect, extras: product.extras, input: pricingInput(state))
    }

    /// Ошибка валидации выбора (например, строка меню ниже минимума).
    func validationError(_ state: ConfiguratorState) -> PricingError? {
        guard let complect = complect(state) else { return nil }
        do {
            _ = try Pricing.calculate(complect: complect, extras: product.extras, input: pricingInput(state))
            return nil
        } catch let error as PricingError {
            return error
        } catch {
            return PricingError(field: "unknown", message: error.userMessage)
        }
    }

    /// Лейбл цены в липком баре: «Аренда», «Купить», «Стоимость».
    func priceLabel(_ state: ConfiguratorState) -> String {
        let complect = complect(state)
        return complect?.side(state.priceType)?.label
            ?? sub(state)?.side(state.priceType)?.label
            ?? (state.priceType == .buy ? String(localized: "Купить") : String(localized: "Аренда"))
    }

    /// Префикс «от» — только пока цена не уточнена вариантом.
    func showsFrom(_ state: ConfiguratorState) -> Bool {
        if let subSide = sub(state)?.side(state.priceType), showsSubs(state) { return subSide.from == true }
        return complect(state)?.side(state.priceType)?.from == true
    }

    func postfix(_ state: ConfiguratorState) -> String? {
        let subPostfix = showsSubs(state) ? sub(state)?.side(state.priceType)?.postfix : nil
        return subPostfix ?? complect(state)?.side(state.priceType)?.postfix
    }

    func minQty(_ state: ConfiguratorState) -> Int {
        guard mode != .cateringMenu else { return 1 }
        let subSide = showsSubs(state) ? sub(state)?.side(state.priceType) : nil
        return max(subSide?.minQty ?? complect(state)?.side(state.priceType)?.minQty ?? 1, 1)
    }

    func stepPct(_ state: ConfiguratorState) -> Double {
        let subSide = showsSubs(state) ? sub(state)?.side(state.priceType) : nil
        return subSide?.qtyStepPct ?? complect(state)?.side(state.priceType)?.qtyStepPct ?? 0
    }

    /// Единица количества: postfix без «/», «за» и цифр → иначе лейбл с числом → «шт».
    func qtyUnit(_ state: ConfiguratorState) -> String {
        if let unit = Self.unitWord(from: postfix(state)) { return unit }
        let label = complect(state)?.side(state.priceType)?.label
        if let label, label.contains(where: \.isNumber), let unit = Self.unitWord(from: label) { return unit }
        return String(localized: "шт")
    }

    static func unitWord(from raw: String?) -> String? {
        guard let raw else { return nil }
        // Постфикс с числом — вместимость/объём комплекта («/ до 40 чел», «/ 40 л.»),
        // а не единица количества: считаем в штуках (как сервер в quote).
        guard !raw.contains(where: \.isNumber) else { return nil }
        var text = raw.replacingOccurrences(of: "/", with: " ")
        text = text.filter { !$0.isNumber }
        let words = text.split(separator: " ").filter { $0.lowercased() != "за" }
        let joined = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    /// Подсказка под ценой: «с 2-го дня — 154 ₽», «доп. час — 7 500 ₽», «доп. порц. — 500 ₽».
    func hint(_ state: ConfiguratorState) -> String? {
        guard let complect = complect(state) else { return nil }
        if let rule = activeTimeRule(state), rule.percent > 0 {
            let subAmount = showsSubs(state) ? (sub(state)?.side(state.priceType)?.amount ?? 0) : 0
            let base = (complect.side(state.priceType)?.amount ?? 0) + subAmount
            let step = Pricing.roundRub(Double(base) * rule.percent / 100)
            guard step > 0 else { return nil }
            switch rule.unit {
            case .hours:
                return String(localized: "доп. час — \(Money.rub(step))")
            case .days, .unknown:
                return String(localized: "с \(rule.defaultValue + 1)-го дня — \(Money.rub(step))")
            }
        }
        let pct = stepPct(state)
        if pct > 0, let unitPrice = price(state)?.unitPrice, unitPrice > 0 {
            let step = Pricing.roundRub(Double(unitPrice) * pct / 100)
            return String(localized: "доп. \(qtyUnit(state)) — \(Money.rub(step))")
        }
        return nil
    }

    /// Жёлтый бейдж срока: «1 день», «6 часов», «за 10 участников».
    func badge(_ state: ConfiguratorState) -> String? {
        if mode == .masterclass { return product.masterclass?.priceBadge }
        guard activeTimeRule(state) != nil, let time = state.time else { return nil }
        switch time.unit {
        case .hours: return String(localized: "\(time.value) часов")
        case .days, .unknown: return String(localized: "\(time.value) дней")
        }
    }

    // MARK: - Extras

    func requiredExtras() -> [String: Int] {
        Dictionary(product.extras.filter(\.isRequired).map { ($0.id, 1) }, uniquingKeysWith: { first, _ in first })
    }

    /// «Дополнительные опции» — допы без группы.
    var plainExtras: [Extra] {
        guard mode != .masterclass else { return [] }
        return product.extras.filter { ($0.group ?? "").isEmpty }
    }

    /// «Также подходит» — допы с группами (фильтр-пилюли).
    var alsoFitsGroups: [String] {
        guard mode != .masterclass else { return [] }
        var seen: [String] = []
        for extra in product.extras {
            if let group = extra.group, !group.isEmpty, !seen.contains(group) { seen.append(group) }
        }
        return seen
    }

    func alsoFits(group: String?) -> [Extra] {
        product.extras.filter { extra in
            guard let own = extra.group, !own.isEmpty else { return false }
            return group == nil || own == group
        }
    }

    func extrasVisible(_ state: ConfiguratorState) -> Bool {
        !(mode == .trampoline && state.priceType == .buy) || product.extras.contains(where: \.isRequired)
    }

    private func extraSelections(_ state: ConfiguratorState) -> [ExtraSelection] {
        product.extras.compactMap { extra -> ExtraSelection? in
            guard let qty = state.extras[extra.id], qty > 0 else { return nil }
            return ExtraSelection(id: extra.id, qty: extra.isCountable ? qty : nil)
        }
    }

    // MARK: - Catering menu

    func menuGroups(_ state: ConfiguratorState) -> [MenuGroup] {
        guard let complect = complect(state) else { return [] }
        var groups: [MenuGroup] = []
        for row in complect.menuRows {
            if let index = groups.firstIndex(where: { $0.title == row.group }) {
                let existing = groups[index]
                groups[index] = MenuGroup(title: existing.title, rows: existing.rows + [row])
            } else {
                groups.append(MenuGroup(title: row.group, rows: [row]))
            }
        }
        return groups
    }

    /// Меню стартует пустым: строка выбирается пользователем, minQty — порог для qty > 0.
    private func defaultMenu(for complect: Complect) -> [String: Int] { [:] }

    private func menuSelections(_ state: ConfiguratorState) -> [MenuSelection] {
        guard let complect = complect(state) else { return [] }
        return complect.menuRows.compactMap { row -> MenuSelection? in
            guard let qty = state.menu[row.id], qty > 0 else { return nil }
            return MenuSelection(id: row.id, qty: qty)
        }
    }

    func menuSum(_ state: ConfiguratorState) -> Int { price(state)?.unitPrice ?? 0 }

    // MARK: - Transitions (возвращают новое состояние)

    /// Тап комплекта: свой набор вариантов, время сохраняется, допы сбрасываются (кроме обязательных).
    func selectingComplect(_ id: Int, from state: ConfiguratorState) -> ConfiguratorState {
        guard let complect = product.complects.first(where: { $0.id == id }), id != state.complectId else { return state }
        var next = state
        next.complectId = id
        let types = availablePriceTypes(complect)
        if !types.contains(next.priceType) { next.priceType = types.first ?? .rent }
        next.subId = defaultSubId(for: complect, priceType: next.priceType, preferred: nil)
        if let rule = complect.time {
            if let current = state.time, current.unit == rule.unit || rule.unit == .hours {
                next.time = clamp(current, to: rule)
            } else {
                next.time = TimeSelection(unit: rule.unit, value: rule.defaultValue)
            }
        } else {
            next.time = nil
        }
        next.extras = requiredExtras()
        next.menu = defaultMenu(for: complect)
        next.qty = max(minQty(next), 1)
        return next
    }

    func selectingSub(_ id: String, from state: ConfiguratorState) -> ConfiguratorState {
        var next = state
        next.subId = id
        next.qty = max(next.qty, minQty(next))
        return next
    }

    func selectingPriceType(_ type: PriceType, from state: ConfiguratorState) -> ConfiguratorState {
        guard let complect = complect(state), availablePriceTypes(complect).contains(type) else { return state }
        var next = state
        next.priceType = type
        if complect.subList.first(where: { $0.id == state.subId })?.side(type) == nil {
            next.subId = defaultSubId(for: complect, priceType: type, preferred: nil)
        }
        next.qty = max(next.qty, minQty(next))
        return next
    }

    func selectingTime(_ time: TimeSelection, from state: ConfiguratorState) -> ConfiguratorState {
        guard let rule = complect(state)?.time else { return state }
        var next = state
        next.time = clamp(time, to: rule)
        return next
    }

    func togglingExtra(_ id: String, from state: ConfiguratorState) -> ConfiguratorState {
        guard let extra = product.extras.first(where: { $0.id == id }), !extra.isRequired else { return state }
        var next = state
        if next.extras[id] != nil {
            next.extras.removeValue(forKey: id)
        } else {
            next.extras[id] = 1
        }
        return next
    }

    func settingExtraQty(_ id: String, qty: Int, from state: ConfiguratorState) -> ConfiguratorState {
        guard let extra = product.extras.first(where: { $0.id == id }) else { return state }
        var next = state
        let minimum = extra.isRequired ? 1 : 0
        let value = max(qty, minimum)
        if value == 0 { next.extras.removeValue(forKey: id) } else { next.extras[id] = value }
        return next
    }

    func settingMenuQty(_ id: String, qty: Int, from state: ConfiguratorState) -> ConfiguratorState {
        guard let row = complect(state)?.menuRows.first(where: { $0.id == id }) else { return state }
        var next = state
        let minimum = max(row.minQty ?? 1, 1)
        let current = state.menu[id] ?? 0
        // Шаг вниз ниже минимума снимает строку, шаг вверх с нуля — сразу к минимуму.
        if qty <= 0 || (qty < minimum && qty < current) {
            next.menu.removeValue(forKey: id)
        } else {
            next.menu[id] = min(max(qty, minimum), Self.maxQty)
        }
        return next
    }

    func settingQty(_ qty: Int, from state: ConfiguratorState) -> ConfiguratorState {
        var next = state
        next.qty = min(max(qty, minQty(state)), Self.maxQty)
        return next
    }

    static let maxQty = 10_000
    static let maxDays = 365

    private func clamp(_ time: TimeSelection, to rule: TimeRule) -> TimeSelection {
        switch rule.unit {
        case .hours where time.unit == .hours:
            return TimeSelection(unit: .hours, value: min(max(time.value, rule.defaultValue), max(Pricing.maxHours, rule.defaultValue)))
        case .hours:
            return TimeSelection(unit: .days, value: min(max(time.value, 2), Self.maxDays))
        case .days, .unknown:
            return TimeSelection(unit: .days, value: min(max(time.value, rule.defaultValue), Self.maxDays))
        }
    }

    private func defaultSubId(for complect: Complect, priceType: PriceType, preferred: String?) -> String? {
        let subs = complect.subList
        guard !subs.isEmpty else { return nil }
        if let preferred, subs.contains(where: { $0.id == preferred }) { return preferred }
        return subs.first(where: { $0.side(priceType) != nil })?.id ?? subs.first?.id
    }

    // MARK: - Cart

    func cartInput(_ state: ConfiguratorState) -> CartItemInput {
        let input = pricingInput(state)
        return CartItemInput(
            productId: product.id,
            complectId: state.complectId,
            subId: input.subId,
            priceType: state.priceType,
            time: input.time,
            qty: mode == .cateringMenu ? 1 : max(state.qty, minQty(state)),
            extras: input.extras.isEmpty ? nil : input.extras,
            menu: input.menu.isEmpty ? nil : input.menu
        )
    }

    /// Восстановить выбор из позиции корзины (повторное открытие карточки).
    func state(from item: CartItemInput) -> ConfiguratorState? {
        guard item.productId == product.id,
              var state = initialState(preselect: ProductPreselection(complectId: item.complectId, subId: item.subId, priceType: item.priceType))
        else { return nil }
        if let time = item.time { state = selectingTime(time, from: state) }
        state.qty = max(item.qty, minQty(state))
        var extras = requiredExtras()
        for selection in item.extras ?? [] { extras[selection.id] = selection.qty ?? 1 }
        state.extras = extras
        if let menu = item.menu {
            state.menu = Dictionary(menu.map { ($0.id, $0.qty) }, uniquingKeysWith: { first, _ in first })
        }
        return state
    }

    /// Ссылка на вариант-страницу сайта для «Поделиться».
    func shareURL(_ state: ConfiguratorState) -> URL? {
        let subId = showsSubs(state) ? state.subId : nil
        if let link = product.variantLinks?.first(where: {
            $0.complectId == state.complectId && $0.subId == subId && ($0.priceType ?? .rent) == state.priceType
        }), let slug = link.slug, !slug.isEmpty {
            return URL(string: "/\(product.slug)/\(slug)/", relativeTo: AppConfig.siteURL)?.absoluteURL
        }
        return product.shareURL
    }

    // MARK: - Breakdown («Итого»)

    func breakdown(_ state: ConfiguratorState) -> [BreakdownSection] {
        guard let complect = complect(state), let price = price(state) else { return [] }
        var sections: [BreakdownSection] = []
        let unit = qtyUnit(state)

        var config: [BreakdownRow] = [BreakdownRow(title: complectsTitle(), value: complect.title)]
        if showsSubs(state), let sub = sub(state) {
            config.append(BreakdownRow(title: subsTitle(state), value: sub.name))
        }
        if availablePriceTypes(complect).count > 1 {
            config.append(BreakdownRow(title: String(localized: "Вид"), value: priceLabel(state)))
        }
        if let badge = badge(state), mode != .masterclass {
            config.append(BreakdownRow(title: String(localized: "Время"), value: badge))
        }
        sections.append(BreakdownSection(title: String(localized: "Конфигурация"), note: nil, rows: config))

        if price.onRequest {
            sections.append(BreakdownSection(
                title: String(localized: "Стоимость"),
                note: nil,
                rows: [BreakdownRow(title: String(localized: "Цена"), value: String(localized: "по запросу"), emphasized: true)]
            ))
            return sections
        }

        var cost: [BreakdownRow] = []
        if mode == .cateringMenu {
            for group in menuGroups(state) {
                for row in group.rows {
                    guard let qty = state.menu[row.id], qty > 0 else { continue }
                    cost.append(BreakdownRow(title: "\(row.name) × \(qty)", value: Money.rub(row.price * qty)))
                }
            }
        } else {
            cost.append(BreakdownRow(title: String(localized: "Цена за 1 \(unit)"), value: Money.rub(price.unitPrice)))
            if price.stepPct > 0 {
                cost.append(BreakdownRow(title: String(localized: "Мин. кол-во × \(price.minQty)"), value: Money.rub(price.unitPrice * price.minQty)))
                let extraUnits = max(0, state.qty - price.minQty)
                if extraUnits > 0 {
                    let stepTotal = Pricing.roundRub(Double(price.unitPrice) * price.stepPct / 100 * Double(extraUnits))
                    cost.append(BreakdownRow(title: String(localized: "Доп. \(extraUnits) \(unit)"), value: "+" + Money.rub(stepTotal)))
                }
            } else {
                if price.minQty > 1 {
                    cost.append(BreakdownRow(title: String(localized: "Мин. кол-во"), value: "\(price.minQty) \(unit)"))
                }
                cost.append(BreakdownRow(title: String(localized: "Кол-во"), value: "× \(price.effectiveQty)"))
            }
        }
        if price.basePrice > 0 {
            cost.append(BreakdownRow(title: complect.basePriceName ?? String(localized: "Выезд"), value: "+" + Money.rub(price.basePrice)))
        }
        if price.reward > 0 {
            cost.append(BreakdownRow(title: complect.reward?.label ?? String(localized: "Скидка"), value: "−" + Money.rub(price.reward)))
        }
        sections.append(BreakdownSection(title: String(localized: "Стоимость"), note: nil, rows: cost))

        let chosenExtras = product.extras.compactMap { extra -> BreakdownRow? in
            guard let qty = state.extras[extra.id], qty > 0 else { return nil }
            let count = extra.isCountable ? qty : 1
            let title = count > 1 ? "\(extra.name) × \(count)" : extra.name
            return BreakdownRow(title: title, value: "+" + Money.rub(extra.price * count))
        }
        if !chosenExtras.isEmpty {
            sections.append(BreakdownSection(
                title: String(localized: "Доп. опции"),
                note: String(localized: "не × кол-во и дни"),
                rows: chosenExtras
            ))
        }

        sections.append(BreakdownSection(
            title: String(localized: "Итого"),
            note: nil,
            rows: [BreakdownRow(title: String(localized: "Итого"), value: Money.rub(price.total), emphasized: true)]
        ))
        return sections
    }
}
