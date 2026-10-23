import Foundation

/// «Акции» и кейсы демо-режима — порт SnapshotContentRepository.php
/// (sale.json, cases.json, cases/{slug}.json набора DemoData).
extension DemoCatalog {
    private static let slugHead = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
    private static let slugBody = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")

    /// Slug кейса как в адресе сайта /cases/{slug}/ (без «..», «/» и прочего).
    static func isCaseSlug(_ slug: String) -> Bool {
        guard let first = slug.unicodeScalars.first, slug.unicodeScalars.count <= 100 else { return false }
        return slugHead.contains(first) && slug.unicodeScalars.allSatisfy { slugBody.contains($0) }
    }

    /// «https://www.art-active24.ru/cases/serpuhov/» → «serpuhov».
    static func caseSlug(fromURL raw: String) -> String? {
        let path = URLComponents(string: raw)?.path ?? raw
        let segments = path.split(separator: "/").map(String.init)
        guard segments.count == 2, segments[0] == "cases" else { return nil }
        let slug = segments[1].lowercased()
        return isCaseSlug(slug) ? slug : nil
    }

    func sale() -> [String: Any] {
        let raw = data.raw("sale.json") as? [String: Any] ?? [:]
        var out: [String: Any] = [
            "title": raw["title"] as? String ?? "Выгодные предложения",
            "items": raw["items"] as? [Any] ?? [Any](),
        ]
        if let url = raw["url"] as? String { out["url"] = url }
        return out
    }

    func cases(categoryId: Int?) -> [String: Any] {
        let raw = data.raw("cases.json") as? [String: Any] ?? [:]
        var items = raw["items"] as? [[String: Any]] ?? []
        if let categoryId {
            items = items.filter { ($0["categoryId"] as? NSNumber)?.intValue == categoryId }
        }
        return [
            "title": raw["title"] as? String ?? "Кейсы",
            "categories": raw["categories"] as? [Any] ?? [Any](),
            "items": items,
        ]
    }

    func caseStudy(slug: String) -> [String: Any]? {
        guard Self.isCaseSlug(slug), var study = data.raw("cases/\(slug).json") as? [String: Any] else { return nil }
        let ids = (study["productIds"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        study["products"] = DemoJSON.object(summaries(ids))
        study.removeValue(forKey: "productIds")
        return study
    }

    /// Плитка кейса на главной получает slug, только если карточка кейса есть в наборе.
    func withCaseSlug(_ item: [String: Any]) -> [String: Any] {
        guard let url = item["url"] as? String, let slug = Self.caseSlug(fromURL: url),
              data.raw("cases/\(slug).json") != nil else { return item }
        var copy = item
        copy["slug"] = slug
        return copy
    }
}
