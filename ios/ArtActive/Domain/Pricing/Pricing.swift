import Foundation

/// Входные данные расчёта одной позиции (как `CartItemInput`, без id товара/комплекта).
struct PricingInput: Hashable, Sendable {
    var priceType: PriceType = .rent
    var subId: String?
    var time: TimeSelection?
    var qty: Int = 1
    var extras: [ExtraSelection] = []
    var menu: [MenuSelection] = []
}

/// Ошибка валидации входа расчёта; `field` — поле, как в `expect.error` векторов и `error.fields` API.
struct PricingError: Error, Equatable, Sendable {
    let field: String
    let message: String
}

/// Результат расчёта. Деньги — целые рубли.
struct PriceResult: Hashable, Sendable {
    /// Цена 1 ед. без допов и базы (для кейтеринг-меню — сумма строк меню).
    let unitPrice: Int
    let total: Int
    /// «2 д» / «7 ч» — nil, если время не применяется.
    let timeLabel: String?
    let onRequest: Bool
    /// Расшифровка для попапа «Итого».
    let extrasTotal: Int
    let basePrice: Int
    let reward: Int
    let effectiveQty: Int
    let minQty: Int
    let stepPct: Double
    let multiplier: Double

    static func onRequest(timeLabel: String?) -> PriceResult {
        PriceResult(unitPrice: 0, total: 0, timeLabel: timeLabel, onRequest: true, extrasTotal: 0,
                    basePrice: 0, reward: 0, effectiveQty: 0, minQty: 1, stepPct: 0, multiplier: 1)
    }
}

/// Клиентский расчёт цены — мгновенный предпросмотр. Источник истины — сервер
/// (`/v1/cart/quote`); совпадение гарантируют общие векторы `contract/pricing-vectors.json`.
///
/// Формулы (docs/DATA-MODEL.md):
/// ```
/// mult(hours, h)  = 1 + (h − def)·pct/100                         h ∈ [def..8]
/// mult(hours, Nд) = (1 + (8 − def)·pct/100) · (1 + 0.30·(N − 1))  N ≥ 2
/// mult(days, d)   = 1 + (d − def)·pct/100                         d ≥ def
/// side.sale → mult = 1
/// unit   = round((complect.side + sub.side) · mult) + sub.flatSurcharge
/// extras = Σ выбранных допов (один раз на позицию)
/// total  = step > 0 : unit·min + unit·step/100·max(0, qty − min) + extras + basePrice
///          иначе    : unit·max(qty, min) + extras + basePrice
/// cateringMenu: total = Σ(row.qty·row.price) + basePrice + Σ(extra.qty·extra.price) − reward
/// округление: floor(x + 0.5 + 1e-9); обязательные допы входят всегда;
/// строка меню с qty > 0 меньше minQty — `PricingError(field: "menu")`
/// ```
enum Pricing {
    /// Максимум часов в почасовой шкале, дальше — дни (если default > 8 — default).
    static let maxHours = 8
    /// Потолок суммы позиции.
    static let maxTotal = 1_000_000_000

    static func hoursCap(_ defaultHours: Int) -> Int { max(maxHours, defaultHours) }

    private static func capped(_ total: Int) throws -> Int {
        guard total <= maxTotal else {
            throw PricingError(field: "total", message: String(localized: "Сумма позиции слишком большая — уменьшите количество"))
        }
        return total
    }

    /// Вариант: обязателен, если хоть у одного варианта есть цена для выбранной стороны
    /// (аренда батута — да; покупка, когда у вариантов нет стороны buy, — нет).
    static func resolveSub(complect: Complect, input: PricingInput) throws -> Sub? {
        guard let id = input.subId else {
            if complect.subList.contains(where: { $0.side(input.priceType) != nil }) {
                throw PricingError(field: "subId", message: String(localized: "Выберите вариант"))
            }
            return nil
        }
        guard let sub = complect.subList.first(where: { $0.id == id }) else {
            throw PricingError(field: "subId", message: String(localized: "Вариант недоступен"))
        }
        return sub
    }
    /// Надбавка за каждый доп. день в почасовом режиме.
    static let extraDayRate = 0.30

    static func calculate(complect: Complect, extras: [Extra], input: PricingInput) throws -> PriceResult {
        if !complect.menuRows.isEmpty {
            return try cateringMenu(complect: complect, extras: extras, input: input)
        }

        let sub = try resolveSub(complect: complect, input: input)
        let complectSide = complect.side(input.priceType)
        let subSide = sub?.side(input.priceType)

        let isSale = complectSide?.sale == true || subSide?.sale == true
        let time = isSale ? nil : timeFactor(rule: complect.time, selection: input.time)

        if complectSide?.onRequest == true || subSide?.onRequest == true {
            return .onRequest(timeLabel: time?.label)
        }

        let multiplier = time?.multiplier ?? 1
        let raw = Double((complectSide?.amount ?? 0) + (subSide?.amount ?? 0)) * multiplier
        // Фикс-надбавка варианта (батут на асфальте) — только для аренды и не × время.
        let flat = input.priceType == .rent ? (sub?.flatSurcharge ?? 0) : 0
        let unit = roundRub(raw) + flat

        let minQty = max(subSide?.minQty ?? complectSide?.minQty ?? 1, 1)
        let stepPct = subSide?.qtyStepPct ?? complectSide?.qtyStepPct ?? 0
        let qty = max(input.qty, 1)

        let extrasTotal = extrasSum(extras: extras, selected: input.extras)
        let base = complect.basePrice ?? 0

        let itemsTotal: Int
        let effectiveQty: Int
        if stepPct > 0 {
            let extraUnits = max(0, qty - minQty)
            itemsTotal = unit * minQty + roundRub(Double(unit) * stepPct / 100 * Double(extraUnits))
            effectiveQty = qty
        } else {
            effectiveQty = max(qty, minQty)
            itemsTotal = unit * effectiveQty
        }

        return PriceResult(
            unitPrice: unit,
            total: try capped(itemsTotal + extrasTotal + base),
            timeLabel: time?.label,
            onRequest: false,
            extrasTotal: extrasTotal,
            basePrice: base,
            reward: 0,
            effectiveQty: effectiveQty,
            minQty: minQty,
            stepPct: stepPct,
            multiplier: multiplier
        )
    }

    // MARK: - Строка-опция (без комплекта)

    /// Допы-опции товара отдельной позицией (orderMode = toggle): Σ допов × qty.
    /// Обязательные допы здесь не добавляются; без допов — ошибка `extras`.
    static func optionLine(extras: [Extra], selected: [ExtraSelection], qty: Int) throws -> PriceResult {
        let byId = Dictionary(extras.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var sum = 0
        var found = 0
        for selection in selected {
            guard let extra = byId[selection.id] else { continue }
            let count = extra.isCountable ? max(selection.qty ?? 1, 1) : 1
            sum += extra.price * count
            found += 1
        }
        guard found > 0 else {
            throw PricingError(field: "extras", message: String(localized: "Выберите хотя бы одну опцию"))
        }
        let quantity = max(qty, 1)
        return PriceResult(
            unitPrice: sum,
            total: try capped(sum * quantity),
            timeLabel: nil,
            onRequest: false,
            extrasTotal: sum,
            basePrice: 0,
            reward: 0,
            effectiveQty: quantity,
            minQty: 1,
            stepPct: 0,
            multiplier: 1
        )
    }

    // MARK: - Time

    struct TimeFactor: Hashable, Sendable {
        let multiplier: Double
        let label: String
    }

    /// Множитель времени. Без правила времени — nil (время не применяется).
    static func timeFactor(rule: TimeRule?, selection: TimeSelection?) -> TimeFactor? {
        guard let rule, rule.unit != .unknown else { return nil }
        let pct = rule.percent / 100
        let def = rule.defaultValue
        let chosen = selection ?? TimeSelection(unit: rule.unit, value: def)

        switch rule.unit {
        case .hours:
            if chosen.unit == .days {
                let days = max(chosen.value, 1)
                let mult8h = 1 + Double(hoursCap(def) - def) * pct
                return TimeFactor(multiplier: mult8h * (1 + extraDayRate * Double(days - 1)), label: "\(days) д")
            }
            let hours = min(max(chosen.value, def), hoursCap(def))
            return TimeFactor(multiplier: 1 + Double(hours - def) * pct, label: "\(hours) ч")
        case .days:
            let days = max(chosen.value, def)
            return TimeFactor(multiplier: 1 + Double(days - def) * pct, label: "\(days) д")
        case .unknown:
            return nil
        }
    }

    // MARK: - Catering menu

    static func cateringMenu(complect: Complect, extras: [Extra], input: PricingInput) throws -> PriceResult {
        let rows = Dictionary(complect.menuRows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var menuSum = 0
        var selectedRows = 0
        for selection in input.menu where selection.qty > 0 {
            guard let row = rows[selection.id] else {
                throw PricingError(field: "menu", message: String(localized: "Позиция меню недоступна"))
            }
            if let minimum = row.minQty, selection.qty < minimum {
                throw PricingError(field: "menu", message: String(localized: "«\(row.name)» — минимум \(minimum)"))
            }
            menuSum += selection.qty * row.price
            selectedRows += 1
        }
        guard selectedRows > 0 else {
            throw PricingError(field: "menu", message: String(localized: "Добавьте хотя бы одну позицию меню"))
        }
        let base = complect.basePrice ?? 0
        let extrasTotal = extrasSum(extras: extras, selected: input.extras)
        let reward = rewardAmount(complect.reward, menuSum: menuSum, basePrice: base)

        return PriceResult(
            unitPrice: menuSum,
            total: try capped(menuSum + base + extrasTotal - reward),
            timeLabel: nil,
            onRequest: complect.rent?.onRequest == true,
            extrasTotal: extrasTotal,
            basePrice: base,
            reward: reward,
            effectiveQty: 1,
            minQty: 1,
            stepPct: 0,
            multiplier: 1
        )
    }

    /// Промо-награда кейтеринга. `base_free` — при сумме меню ≥ цели выезд бесплатно.
    /// `every_nth` на живых карточках не встречен — сервер считает его сам, клиент не вычитает.
    static func rewardAmount(_ reward: Reward?, menuSum: Int, basePrice: Int) -> Int {
        guard let reward, let goal = reward.goal, goal > 0, menuSum >= goal else { return 0 }
        switch reward.type {
        case .baseFree: return basePrice
        default: return 0
        }
    }

    /// Прогресс к цели награды (0…1) — для шкалы «до бесплатного выезда».
    static func rewardProgress(_ reward: Reward?, menuSum: Int) -> Double? {
        guard let goal = reward?.goal, goal > 0 else { return nil }
        return min(Double(menuSum) / Double(goal), 1)
    }

    // MARK: - Helpers

    /// Сумма допов. Обязательные (`required`) входят всегда, даже если клиент их не прислал.
    static func extrasSum(extras: [Extra], selected: [ExtraSelection]) -> Int {
        let chosen = Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return extras.reduce(0) { sum, extra in
            let qty: Int
            if let selection = chosen[extra.id] {
                qty = extra.isCountable ? max(selection.qty ?? 1, extra.isRequired ? 1 : 0) : 1
            } else if extra.isRequired {
                qty = 1
            } else {
                return sum
            }
            return sum + extra.price * qty
        }
    }

    /// Округление до рубля по контракту: floor(x + 0.5 + 1e-9) — половина вверх,
    /// с допуском на шум двоичной арифметики (770 × 1.2 = 923.9999…).
    static func roundRub(_ value: Double) -> Int {
        Int((value + 0.5 + 1e-9).rounded(.down))
    }
}
