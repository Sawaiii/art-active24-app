import Foundation

/// Раздел из categories.json (формат снапшота, см. api/src/Catalog/Snapshot).
struct DemoCategory: Decodable, Sendable {
    let id: Int
    let parentId: Int?
    let name: String
    let slug: String?
    let url: String?
    let icon: String?
    let image: String?
    let kind: CategoryKind
    let sort: Int?
    let inMenu: Bool?
    let title: String?
    let heroVideo: String?
    let seoHtml: String?
    let scenarios: [Scenario]?

    func node(children: [CategoryNode]? = nil) -> CategoryNode {
        CategoryNode(id: id, name: name, slug: slug, url: url, icon: icon, image: image, kind: kind, children: children)
    }
}

/// Служебные поля товара из products.json (для фильтров, сортировки и поиска).
struct DemoProductFacts: Decodable, Sendable {
    let id: Int
    let slug: String
    let name: String
    let price: PriceTag?
    let categoryIds: [Int]?
    let colors: [String]?
    let sortPopular: Int?
    let createdRank: Int?
}

struct DemoProductEntry: Sendable {
    let summary: ProductSummary
    let facts: DemoProductFacts
}

/// Служебные поля площадки из venues.json (фасеты, подборки, диапазоны).
struct DemoVenueFacts: Decodable, Sendable {
    let id: Int
    let slug: String
    let events: [Int]?
    let types: [Int]?
    let metroIds: [Int]?
    let props: [Int]?
    let collections: [Int]?
    let priceAmount: Int?
    let capacity: Int?
    let area: Int?
    let sortPopular: Int?
}

struct DemoVenueEntry: Sendable {
    let summary: VenueSummary
    let facts: DemoVenueFacts
}

/// Встроенный набор данных (папка DemoData в бандле = api/tests/fixtures/demo).
final class DemoDataset: @unchecked Sendable {
    let categories: [DemoCategory]
    let categoriesById: [Int: DemoCategory]
    let products: [DemoProductEntry]
    let productsById: [Int: DemoProductEntry]
    let venues: [DemoVenueEntry]

    private let directory: URL
    private let lock = NSLock()
    private var productCache: [Int: Product] = [:]

    init(directory: URL) throws {
        self.directory = directory
        let decoder = JSONCoding.makeDecoder()
        func read(_ name: String) throws -> Data {
            try Data(contentsOf: directory.appendingPathComponent(name))
        }

        let categories = try decoder.decode([DemoCategory].self, from: read("categories.json"))
        self.categories = categories
        categoriesById = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let productsData = try read("products.json")
        let summaries = try decoder.decode([ProductSummary].self, from: productsData)
        let productFacts = try decoder.decode([DemoProductFacts].self, from: productsData)
        let products = zip(summaries, productFacts).map { DemoProductEntry(summary: $0, facts: $1) }
        self.products = products
        productsById = Dictionary(products.map { ($0.summary.id, $0) }, uniquingKeysWith: { first, _ in first })

        let venuesData = try read("venues.json")
        let venueSummaries = try decoder.decode([VenueSummary].self, from: venuesData)
        let venueFacts = try decoder.decode([DemoVenueFacts].self, from: venuesData)
        venues = zip(venueSummaries, venueFacts).map { DemoVenueEntry(summary: $0, facts: $1) }
    }

    /// Папка в бандле приложения (folder reference: «DemoData» или исходное имя «demo»).
    static func bundled(_ bundle: Bundle = .main) -> DemoDataset? {
        for name in ["DemoData", "demo"] {
            guard let url = bundle.url(forResource: name, withExtension: nil),
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("categories.json").path) else { continue }
            return try? DemoDataset(directory: url)
        }
        return nil
    }

    /// JSON-файл набора как есть (home.json, info.json, venues/{id}.json …).
    func raw(_ relativePath: String) -> Any? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(relativePath)) else { return nil }
        return DemoJSON.parse(data)
    }

    /// Карточка товара: есть в каталоге и есть файл products/{id}.json.
    func productRaw(_ id: Int) -> Any? {
        guard productsById[id] != nil else { return nil }
        return raw("products/\(id).json")
    }

    func product(_ id: Int) -> Product? {
        lock.lock()
        if let cached = productCache[id] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        guard productsById[id] != nil,
              let data = try? Data(contentsOf: directory.appendingPathComponent("products/\(id).json")),
              let product = try? JSONCoding.makeDecoder().decode(Product.self, from: data) else { return nil }
        lock.lock()
        productCache[id] = product
        lock.unlock()
        return product
    }

    func venueRaw(_ id: Int) -> Any? {
        raw("venues/\(id).json")
    }

    func venueName(_ id: Int) -> String? {
        (venueRaw(id) as? [String: Any])?["name"] as? String
    }
}
