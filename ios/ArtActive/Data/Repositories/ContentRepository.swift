import Foundation

/// «Акции» и кейсы («Примеры работ»).
protocol ContentRepository: Sendable {
    func sale() async throws -> SalePayload
    func cases(categoryId: Int?) async throws -> CaseListPayload
    func caseStudy(slug: String) async throws -> CaseStudy
}

struct LiveContentRepository: ContentRepository {
    let client: APIClient

    func sale() async throws -> SalePayload {
        try await client.request(.get("/v1/sale", cacheable: true))
    }

    func cases(categoryId: Int?) async throws -> CaseListPayload {
        var query: [URLQueryItem] = []
        query.append("category", categoryId)
        return try await client.request(.get("/v1/cases", query: query, cacheable: true))
    }

    func caseStudy(slug: String) async throws -> CaseStudy {
        let safe = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? slug
        return try await client.request(.get("/v1/cases/\(safe)", cacheable: true))
    }
}
