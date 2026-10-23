import Foundation

/// Ответ встроенного демо-бэкенда: HTTP-статус и тело (конверт `{success, data, error, meta}`).
struct DemoResponse: Sendable {
    let status: Int
    let body: Data
}

/// Ошибка как `HttpError` PHP-API: статус, машинный код, текст и ошибки полей.
struct DemoError: Error, Sendable {
    let status: Int
    let code: String
    let message: String
    var fields: [String: String] = [:]

    static func validation(_ fields: [String: String]) -> DemoError {
        DemoError(status: 422, code: "validation_failed", message: "Проверьте правильность заполнения", fields: fields)
    }

    static func notFound(_ what: String = "Ресурс") -> DemoError {
        DemoError(status: 404, code: "not_found", message: "\(what) не найден")
    }

    static func unauthorized(_ message: String = "Требуется вход") -> DemoError {
        DemoError(status: 401, code: "unauthorized", message: message)
    }

    static func badRequest(_ code: String, _ message: String) -> DemoError {
        DemoError(status: 400, code: code, message: message)
    }
}

/// JSON-утилиты демо-бэкенда (повторяют `Response.php`: null-ключи внутри data опускаются).
enum DemoJSON {
    static func parse(_ data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func withoutNulls(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, item) in dict where !(item is NSNull) {
                out[key] = withoutNulls(item)
            }
            return out
        }
        if let array = value as? [Any] {
            return array.map { withoutNulls($0) }
        }
        return value
    }

    /// Encodable-модель контракта → JSON-объект (даты ISO-8601, nil-поля не пишутся).
    static func object<T: Encodable>(_ value: T) -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value), let object = parse(data) else { return NSNull() }
        return object
    }

    static func ok(_ data: Any, meta: [String: Any]? = nil, status: Int = 200) -> DemoResponse {
        var body: [String: Any] = ["success": true, "data": withoutNulls(data), "error": NSNull()]
        if let meta { body["meta"] = meta }
        return DemoResponse(status: status, body: serialize(body))
    }

    static func noContent() -> DemoResponse {
        DemoResponse(status: 204, body: Data())
    }

    static func error(_ error: DemoError) -> DemoResponse {
        var payload: [String: Any] = ["code": error.code, "message": error.message]
        if !error.fields.isEmpty { payload["fields"] = error.fields }
        return DemoResponse(status: error.status, body: serialize(["success": false, "data": NSNull(), "error": payload]))
    }

    static func serialize(_ object: Any) -> Data {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: []) else {
            return Data("{}".utf8)
        }
        return data
    }

    static func pageMeta(total: Int, page: Int, limit: Int) -> [String: Any] {
        ["total": total, "page": page, "limit": limit]
    }
}

/// Доступ к полям JSON-тела запроса с проверкой типов (как `is_int`/`is_string` в PHP).
extension Dictionary where Key == String, Value == Any {
    func demoString(_ key: String) -> String? {
        self[key] as? String
    }

    /// Целое число (не bool и не дробное).
    func demoInt(_ key: String) -> Int? {
        guard let number = self[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.rounded() == value, abs(value) < 9_000_000_000_000 else { return nil }
        return number.intValue
    }

    func demoHas(_ key: String) -> Bool {
        guard let value = self[key] else { return false }
        return !(value is NSNull)
    }
}
