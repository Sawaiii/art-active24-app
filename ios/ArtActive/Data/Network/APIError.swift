import Foundation

/// Тело ошибки из конверта `{success:false, error:{code, message, fields}}`.
struct APIErrorPayload: Codable, Hashable, Sendable {
    let code: String
    let message: String
    let fields: [String: String]?
}

/// Все ошибки сетевого слоя приводятся к этому типу; экраны показывают `userMessage`.
enum APIError: Error, Equatable, Sendable {
    case offline
    case timeout
    case cancelled
    case unauthorized
    case server(status: Int, code: String, message: String, fields: [String: String])
    case http(status: Int)
    case decoding(String)
    case invalidResponse

    var userMessage: String {
        switch self {
        case .offline:
            return String(localized: "Нет соединения с интернетом. Проверьте сеть и попробуйте ещё раз.")
        case .timeout:
            return String(localized: "Сервер долго не отвечает. Попробуйте ещё раз.")
        case .cancelled:
            return String(localized: "Запрос отменён.")
        case .unauthorized:
            return String(localized: "Сессия истекла. Войдите снова.")
        case let .server(status, code, message, _):
            // Локальная строка по code/status; серверный текст — запасной вариант.
            if let local = Self.localMessage(code: code, status: status) { return local }
            return message.isEmpty ? String(localized: "Сервер вернул ошибку. Попробуйте позже.") : message
        case let .http(status) where status >= 500:
            return String(localized: "Сервер временно недоступен. Попробуйте позже.")
        case .http(404):
            return String(localized: "Ничего не найдено — возможно, страница удалена.")
        case .http:
            return String(localized: "Не удалось выполнить запрос. Попробуйте ещё раз.")
        case .decoding:
            return String(localized: "Не удалось прочитать ответ сервера. Обновите приложение или попробуйте позже.")
        case .invalidResponse:
            return String(localized: "Некорректный ответ сервера.")
        }
    }

    /// Известные коды ошибок контракта и HTTP-статусы → понятный текст на языке приложения.
    static func localMessage(code: String, status: Int) -> String? {
        switch code {
        case "sms_unavailable":
            return String(localized: "Не удалось отправить SMS. Попробуйте позже или позвоните нам.")
        case "cart_changed":
            return String(localized: "Состав корзины изменился — проверьте позиции и отправьте заявку ещё раз.")
        case "invalid_code", "code_invalid", "code_expired":
            return String(localized: "Неверный или устаревший код. Запросите новый.")
        case "rate_limited", "too_many_requests":
            return String(localized: "Слишком много попыток. Подождите немного.")
        case "not_cancellable":
            return String(localized: "Заявку уже нельзя отменить — свяжитесь с менеджером.")
        default:
            break
        }
        switch status {
        case 400, 422: return nil // текст про конкретное поле приходит с сервера
        case 401: return String(localized: "Сессия истекла. Войдите снова.")
        case 403: return String(localized: "Недостаточно прав для этого действия.")
        case 404: return String(localized: "Ничего не найдено — возможно, страница удалена.")
        case 409: return String(localized: "Данные изменились — обновите экран и попробуйте ещё раз.")
        case 429: return String(localized: "Слишком много попыток. Подождите немного.")
        case 500...599: return String(localized: "Сервер временно недоступен. Попробуйте позже.")
        default: return nil
        }
    }

    /// Ошибки полей формы (`error.fields`).
    var fieldErrors: [String: String] {
        if case let .server(_, _, _, fields) = self { return fields }
        return [:]
    }

    var statusCode: Int? {
        switch self {
        case let .server(status, _, _, _): return status
        case let .http(status): return status
        default: return nil
        }
    }

    var isConnectivity: Bool { self == .offline || self == .timeout }
}

extension APIError: LocalizedError {
    var errorDescription: String? { userMessage }
}

extension Error {
    /// Понятное пользователю сообщение для любой ошибки.
    var userMessage: String {
        if let api = self as? APIError { return api.userMessage }
        if self is DecodingError { return APIError.decoding("").userMessage }
        return String(localized: "Что-то пошло не так. Попробуйте ещё раз.")
    }

    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let api = self as? APIError, api == .cancelled { return true }
        if let url = self as? URLError, url.code == .cancelled { return true }
        return false
    }
}
