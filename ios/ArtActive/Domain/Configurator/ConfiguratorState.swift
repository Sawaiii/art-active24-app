import Foundation

/// Выбор пользователя в конфигураторе (шаблон 128).
struct ConfiguratorState: Hashable, Sendable {
    var complectId: Int
    var subId: String?
    var priceType: PriceType
    var time: TimeSelection?
    var qty: Int
    /// id допа → количество (для несчётных допов всегда 1).
    var extras: [String: Int]
    /// id строки меню → количество (cateringMenu).
    var menu: [String: Int]
}

/// Предвыбор из deep link / вариант-URL.
struct ProductPreselection: Hashable, Sendable {
    var complectId: Int?
    var subId: String?
    var priceType: PriceType?
}

/// Группа вариантов («Привозим готовое», «Готовим на месте»…).
struct SubGroup: Hashable, Sendable, Identifiable {
    let title: String?
    let subs: [Sub]
    var id: String { title ?? "_" + (subs.first?.id ?? "") }
}

/// Группа строк меню кейтеринга.
struct MenuGroup: Hashable, Sendable, Identifiable {
    let title: String?
    let rows: [MenuRow]
    var id: String { title ?? "_" + (rows.first?.id ?? "") }
}

/// Пункт сегмента времени.
enum TimeOption: Hashable, Sendable, Identifiable {
    case value(TimeSelection)
    /// «ещё» — ручной ввод количества дней.
    case more

    var id: String {
        switch self {
        case let .value(selection): return "\(selection.unit.rawValue)-\(selection.value)"
        case .more: return "more"
        }
    }

    var shortTitle: String {
        switch self {
        case let .value(selection):
            return selection.unit == .hours
                ? String(localized: "\(selection.value) ч")
                : String(localized: "\(selection.value) д")
        case .more:
            return String(localized: "ещё")
        }
    }
}

/// Набор вариантов времени для комплекта.
struct TimeOptions: Hashable, Sendable {
    let rule: TimeRule
    /// Основная шкала: часы def…8 либо дни def…def+5.
    let primary: [TimeOption]
    /// Для почасовых — дни (≥2) после 8 часов.
    let days: [TimeOption]
    /// Минимум для ручного ввода «ещё».
    let moreMinimum: Int
}

/// Строка расшифровки «Итого».
struct BreakdownRow: Hashable, Sendable, Identifiable {
    let title: String
    let value: String
    var emphasized = false
    var id: String { title + "|" + value }
}

struct BreakdownSection: Hashable, Sendable, Identifiable {
    let title: String
    let note: String?
    let rows: [BreakdownRow]
    var id: String { title }
}
