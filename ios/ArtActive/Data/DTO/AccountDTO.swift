import Foundation

enum UserRole: String, ResilientEnum {
    case customer, manager, unknown
    static var unknownCase: UserRole { .unknown }
}

struct User: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let phone: String
    let name: String?
    let email: String?
    let company: String?
    let role: UserRole?
}

struct AuthSession: Codable, Hashable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: User
    let isNew: Bool?
}

struct CodeRequest: Encodable, Sendable { let phone: String }

struct CodeResponse: Codable, Hashable, Sendable {
    let resendIn: Int?
    let codeLength: Int?
}

struct VerifyRequest: Encodable, Sendable {
    let phone: String
    let code: String
}

struct RefreshRequest: Encodable, Sendable { let refreshToken: String }

struct ProfilePatch: Encodable, Sendable {
    let name: String?
    let email: String?
    let company: String?
}

struct FavoritesRequest: Encodable, Sendable { let productIds: [Int] }

struct DeviceRequest: Encodable, Sendable {
    let platform: String
    let token: String
}

struct DeviceTokenRequest: Encodable, Sendable { let token: String }

struct SocialLink: Codable, Hashable, Sendable {
    let name: String?
    let url: String?
}

struct Rating: Codable, Hashable, Sendable {
    let value: Double?
    let reviews: Int?
    let source: String?
}

/// Контакты, доставка, условия аренды, самовывоз (`/v1/info`).
struct InfoPayload: Codable, Hashable, Sendable {
    let phone: String?
    let phoneHint: String?
    let email: String?
    let address: String?
    let pickupAddress: String?
    let pickupHours: String?
    let geo: GeoPoint?
    let telegram: String?
    let whatsapp: String?
    /// Чат в мессенджере Max; нет — кнопки Max нет.
    let max: String?
    let socials: [SocialLink]?
    let deliveryHtml: String?
    let rentalTermsHtml: String?
    let cartNotice: String?
    let rating: Rating?

    /// Значения по умолчанию с сайта — пока /v1/info не загрузился.
    static var fallback: InfoPayload { InfoPayload(
        phone: "+74950326750",
        phoneHint: String(localized: "Работаем круглосуточно"),
        email: "info@art-active24.ru",
        address: String(localized: "Москва, Егорьевский проезд, 2А стр. 6"),
        pickupAddress: String(localized: "Москва, Егорьевский проезд, 2Ас6"),
        pickupHours: String(localized: "Пн.-Вс., круглосуточно"),
        geo: nil,
        telegram: nil,
        whatsapp: nil,
        max: nil,
        socials: nil,
        deliveryHtml: nil,
        rentalTermsHtml: nil,
        cartNotice: nil,
        rating: Rating(value: 5.0, reviews: 430, source: String(localized: "Яндекс"))
    ) }
}
