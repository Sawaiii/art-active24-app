import Foundation

/// Деньги — целые рубли, формат по Locale.current: «1 540 ₽» (ru), «RUB 1,540» (en).
enum Money {
    private static let style = IntegerFormatStyle<Int>.Currency(code: "RUB").precision(.fractionLength(0))

    static func rub(_ value: Int) -> String { value.formatted(style) }

    /// Число без валюты с разрядами текущей локали.
    static func digits(_ value: Int) -> String { value.formatted(.number) }

    /// Символ рубля в текущей локали (для раздельной вёрстки «1 540» + серый «₽»).
    static let currencySymbol: String = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "RUB"
        formatter.locale = .current
        return formatter.currencySymbol ?? "₽"
    }()

    /// Цена листинга: «от 1 400 ₽ / порц.», «по запросу».
    static func tag(_ tag: PriceTag?) -> String {
        guard let tag else { return "" }
        if tag.onRequest == true { return String(localized: "по запросу") }
        guard let amount = tag.amount else { return "" }
        var text = tag.from == true ? String(localized: "от \(rub(amount))") : rub(amount)
        if let unit = tag.unit, !unit.isEmpty { text += " " + unit }
        return text
    }
}

/// Даты для экранов — в формате текущей локали.
enum DateText {
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year())
    }

    static func dayShort(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// `YYYY-MM-DD` → «16 октября 2026».
    static func day(fromAPI raw: String?) -> String? {
        guard let raw, let date = DayDate.date(from: raw) else { return nil }
        return day(date)
    }

    static func range(from: String?, to: String?) -> String? {
        guard let start = day(fromAPI: from) else { return nil }
        guard let end = day(fromAPI: to), to != from else { return start }
        return "\(start) — \(end)"
    }
}

/// Телефон РФ: маска «+7 (999) 999-99-99» и нормализация «+79991234567».
enum PhoneFormatter {
    static let digitsCount = 10

    /// 10 значащих цифр без кода страны.
    static func nationalDigits(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        let isDigit: (Character) -> Bool = { $0.isASCII && $0.isNumber }
        var digits: String
        if trimmed.hasPrefix("+7") {
            digits = String(trimmed.dropFirst(2)).filter(isDigit)
        } else {
            digits = trimmed.filter(isDigit)
            if digits.count == digitsCount + 1, let first = digits.first, first == "7" || first == "8" {
                digits.removeFirst()
            }
        }
        return String(digits.prefix(digitsCount))
    }

    static func masked(_ input: String) -> String {
        let digits = Array(nationalDigits(from: input))
        guard !digits.isEmpty else { return "" }
        var out = "+7 ("
        for (index, digit) in digits.enumerated() {
            switch index {
            case 3: out += ") "
            case 6, 8: out += "-"
            default: break
            }
            out.append(digit)
        }
        return out
    }

    static func e164(_ input: String) -> String? {
        let digits = nationalDigits(from: input)
        return digits.count == digitsCount ? "+7" + digits : nil
    }

    /// Любой номер РФ (для контактов заказа допустим городской +7 3xx…).
    static func isValid(_ input: String) -> Bool { e164(input) != nil }

    /// Вход — только мобильный: 10 цифр, начинается с 9.
    static func isMobile(_ input: String) -> Bool {
        let digits = nationalDigits(from: input)
        return digits.count == digitsCount && digits.first == "9"
    }

    /// «+79991234567» → «+7 (999) 123-45-67».
    static func display(_ e164: String) -> String { masked(e164) }
}

enum Validation {
    static func isEmail(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".") && !domain.hasSuffix(".") && !trimmed.contains(" ")
    }
}
