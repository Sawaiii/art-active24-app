import Foundation

// «Акции» (/v1/sale) и кейсы — «Примеры работ» (/v1/cases, /v1/cases/{slug}).

/// «Выгодные предложения» — страница /sale/ сайта. Предложения — плитки `HomeItem`
/// (title, subtitle — текст, image, badge — метка «Бонус»/«Скидка»).
struct SalePayload: Codable, Hashable, Sendable {
    let title: String?
    let url: String?
    let items: [HomeItem]?
}

/// Рубрика кейсов («Кейтеринг», «Тимбилдинг»…).
struct CaseCategory: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let name: String
    let count: Int?
}

/// Плитка кейса в списке и в «Похожих кейсах». Обложка 16:9 (720×405).
struct CaseSummary: Codable, Hashable, Identifiable, Sendable {
    let slug: String
    let title: String
    let image: String?
    /// Как на сайте: «300 000 ₽» или «по запросу».
    let budget: String?
    let budgetAmount: Int?
    let guests: Int?
    let categoryId: Int?

    var id: String { slug }
}

struct CaseListPayload: Codable, Hashable, Sendable {
    let title: String?
    let categories: [CaseCategory]?
    let items: [CaseSummary]?
}

/// Блок текста кейса: «Задача», «Решение».
struct CaseSection: Codable, Hashable, Sendable {
    let title: String
    let html: String
}

/// Позиция «Что было на мероприятии», которой нет среди товаров: раздел каталога или страница сайта.
struct CaseLink: Codable, Hashable, Sendable {
    let title: String
    let image: String?
    let categoryId: Int?
    let url: String
}

/// Карточка кейса.
struct CaseStudy: Codable, Hashable, Sendable {
    let slug: String
    let title: String
    let url: String?
    let description: String?
    let image: String?
    let budget: String?
    let budgetAmount: Int?
    let guests: Int?
    let categoryId: Int?
    let category: CaseCategory?
    /// Фото 4:3 (800×600) и видео с мероприятия.
    let media: [MediaItem]?
    let sections: [CaseSection]?
    let products: [ProductSummary]?
    let links: [CaseLink]?
    let similar: [CaseSummary]?

    var shareURL: URL? { url?.resolvedURL }
}
