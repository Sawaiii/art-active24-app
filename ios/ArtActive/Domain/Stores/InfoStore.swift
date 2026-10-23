import Foundation
import Observation
import UIKit

/// Контакты, доставка, условия (`/v1/info`) и действия связи с менеджером.
@MainActor
@Observable
final class InfoStore {
    private(set) var info: InfoPayload = .fallback
    private(set) var isLoaded = false

    @ObservationIgnored private let repository: ProfileRepository

    init(repository: ProfileRepository) {
        self.repository = repository
    }

    func load() async {
        do {
            info = try await repository.info()
            isLoaded = true
        } catch {
            // Остаются значения по умолчанию с сайта.
        }
    }

    var phoneURL: URL? {
        guard let phone = info.phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "tel:\(digits)")
    }

    var telegramURL: URL? { Self.messengerURL(info.telegram, base: "https://t.me/") }
    var whatsappURL: URL? {
        guard let raw = info.whatsapp, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        let digits = raw.filter(\.isNumber)
        return digits.isEmpty ? nil : URL(string: "https://wa.me/\(digits)")
    }

    /// Max: только готовая ссылка https (на сайте чат открывает JS-виджет, адреса в HTML нет).
    var maxURL: URL? {
        guard let raw = info.max?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "max" else { return nil }
        return url
    }

    var emailURL: URL? {
        guard let email = info.email, !email.isEmpty else { return nil }
        return URL(string: "mailto:\(email)")
    }

    private static func messengerURL(_ raw: String?, base: String) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http") || raw.hasPrefix("tg:") { return URL(string: raw) }
        let handle = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
        return URL(string: base + handle)
    }

    func open(_ url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url)
    }
}
