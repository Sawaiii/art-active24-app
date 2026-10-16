import Foundation

/// Общие JSON-кодеры. Моменты времени — ISO-8601 UTC (с долями секунды и без),
/// календарные даты (`YYYY-MM-DD`) в DTO хранятся строками и разбираются `DayDate`.
enum JSONCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISODate.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Неверный формат даты: \(raw)")
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try makeEncoder().encode(value)
    }
}

/// Разбор ISO-8601 моментов времени.
enum ISODate {
    static func parse(_ raw: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = try? withFraction.parse(raw) { return date }
        let plain = Date.ISO8601FormatStyle()
        if let date = try? plain.parse(raw) { return date }
        return DayDate.date(from: raw)
    }
}

/// Календарная дата `YYYY-MM-DD` в локальном календаре (без сдвигов часовых поясов).
enum DayDate {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func date(from raw: String) -> Date? {
        let parts = raw.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func string(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func startOfToday() -> Date {
        calendar.startOfDay(for: Date())
    }
}
