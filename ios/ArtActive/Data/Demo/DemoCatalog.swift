import Foundation

/// Нормализация для поиска (TextNormalizer.php): нижний регистр, ё → е, всё кроме букв/цифр → пробел.
enum DemoText {
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        var out = ""
        var lastWasSpace = false
        for scalar in lowered.unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    static func words(_ text: String) -> [String] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }
        var seen: [String] = []
        for word in normalized.split(separator: " ").map(String.init) where !seen.contains(word) {
            seen.append(word)
        }
        return seen
    }
}

/// Канонические названия цветов фильтра (ColorPalette.php).
enum DemoColorPalette {
    private static let map: [(String, String)] = [
        ("белый", "#FFFFFF"), ("черный", "#1A1A1A"), ("серый", "#9E9E9E"), ("бежевый", "#E8D9C0"),
        ("коричневый", "#7B4B2A"), ("красный", "#E53935"), ("бордовый", "#7B1E2B"), ("розовый", "#F48FB1"),
        ("оранжевый", "#FB8C00"), ("желтый", "#FDD835"), ("зеленый", "#43A047"), ("оливковый", "#808000"),
        ("голубой", "#64B5F6"), ("синий", "#1E40AF"), ("бирюзовый", "#26C6DA"), ("фиолетовый", "#7E57C2"),
        ("золотой", "#D4AF37"), ("серебряный", "#C0C0C0"), ("прозрачный", "#F5F5F7"), ("дерево", "#A0703C"),
        ("натуральный", "#C8A27A"), ("капучино", "#B79E86"), ("графит", "#3D3D3D"), ("хром", "#D9D9D9"),
    ]
    private static let lookup = Dictionary(map, uniquingKeysWith: { first, _ in first })

    static func hex(_ name: String) -> String? {
        known(normalize(name)).flatMap { lookup[$0] }
    }

    /// «Чёрный»/«черный» → «Черный», «Золото» → «Золотой»; неизвестный — с заглавной буквы.
    static func canonical(_ name: String) -> String {
        let normalized = normalize(name)
        let key = known(normalized) ?? normalized
        guard let first = key.first else { return key }
        return String(first).uppercased() + key.dropFirst()
    }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    private static func known(_ normalized: String) -> String? {
        if lookup[normalized] != nil { return normalized }
        // Род и число прилагательного: «белая», «белое», «белые» → «белый».
        for suffix in ["ая", "яя", "ое", "ее", "ые", "ие"] where normalized.hasSuffix(suffix) && normalized.count > suffix.count {
            let stem = String(normalized.dropLast(suffix.count))
            for ending in ["ый", "ий", "ой"] where lookup[stem + ending] != nil {
                return stem + ending
            }
        }
        guard normalized.count >= 4 else { return nil }
        for (color, _) in map where normalized.hasPrefix(String(color.prefix(4))) {
            return color
        }
        return nil
    }
}

/// Параметры листинга раздела (ProductQuery.php).
struct DemoProductQuery: Sendable {
    var categoryId: Int
    var sort = "popular"
    var priceMin: Int?
    var priceMax: Int?
    var colors: [String] = []
    var page = 1
    var limit = 24

    var offset: Int { (page - 1) * limit }
}

/// Фильтры площадок (VenueQuery.php): внутри группы — ИЛИ, между группами — И, удобства — все.
struct DemoVenueQuery: Sendable {
    var events: [Int] = []
    var types: [Int] = []
    var metro: [Int] = []
    var props: [Int] = []
    var ranges: [String: (Int?, Int?)] = [:]
    var collection: Int?
    var page = 1
    var limit = 24
}

/// Каталог, поиск, главная и площадки поверх встроенного набора (порт Snapshot*Repository.php).
struct DemoCatalog: Sendable {
    let data: DemoDataset

    // MARK: - Дерево и раздел

    func tree() -> [CategoryNode] { children(of: nil, deep: true) }

    func categoryPage(_ id: Int) -> CategoryPage? {
        guard let category = data.categoriesById[id] else { return nil }
        return CategoryPage(
            category: category.node(),
            title: category.title ?? category.name,
            heroVideo: category.heroVideo,
            breadcrumbs: ancestors(of: category),
            children: children(of: id, deep: false),
            scenarios: category.scenarios ?? [],
            seoHtml: category.seoHtml
        )
    }

    private func children(of parentId: Int?, deep: Bool) -> [CategoryNode] {
        // В меню — только разделы из меню сайта; остальные доступны по ссылке и поиску.
        let list = data.categories.enumerated()
            .filter { $0.element.parentId == parentId && $0.element.inMenu != false }
            .sorted { ($0.element.sort ?? 0, $0.offset) < ($1.element.sort ?? 0, $1.offset) }
            .map { $0.element }
        return list.map { category in
            category.node(children: deep ? children(of: category.id, deep: true) : nil)
        }
    }

    private func ancestors(of category: DemoCategory) -> [Crumb] {
        var chain: [Crumb] = []
        var parentId = category.parentId
        while let id = parentId, let parent = data.categoriesById[id], chain.count < 10 {
            chain.insert(Crumb(id: parent.id, name: parent.name), at: 0)
            parentId = parent.parentId
        }
        return chain
    }

    // MARK: - Листинг

    func listProducts(_ query: DemoProductQuery) -> (items: [ProductSummary], total: Int, facets: ProductFacets) {
        let inCategory = data.products.filter { ($0.facts.categoryIds ?? []).contains(query.categoryId) }
        let listFacets = facets(for: inCategory)
        let filtered = inCategory.enumerated()
            .filter { matches($0.element, query) }
            .sorted { lhs, rhs in
                let left = sortKey(lhs.element, query.sort)
                let right = sortKey(rhs.element, query.sort)
                return left != right ? left.lexicographicallyPrecedes(right) : lhs.offset < rhs.offset
            }
            .map { $0.element }
        let page = Array(filtered.dropFirst(query.offset).prefix(query.limit)).map(\.summary)
        return (page, filtered.count, listFacets)
    }

    private func matches(_ product: DemoProductEntry, _ query: DemoProductQuery) -> Bool {
        let price = product.facts.price
        if query.priceMin != nil || query.priceMax != nil {
            guard let amount = price?.amount, price?.onRequest != true else { return false }
            if let min = query.priceMin, amount < min { return false }
            if let max = query.priceMax, amount > max { return false }
        }
        guard !query.colors.isEmpty else { return true }
        let wanted = Set(query.colors.map(DemoColorPalette.canonical))
        let has = Set((product.facts.colors ?? []).map(DemoColorPalette.canonical))
        return !wanted.isDisjoint(with: has)
    }

    /// Ключ сортировки; «по запросу» и без цены при сортировке по цене — в конце.
    private func sortKey(_ product: DemoProductEntry, _ sort: String) -> [Int] {
        let price = product.facts.price
        let noPrice = price?.onRequest == true || price?.amount == nil ? 1 : 0
        let amount = price?.amount ?? 0
        let popular = product.facts.sortPopular ?? Int.max
        switch sort {
        case "price_low": return [noPrice, amount, popular]
        case "price_high": return [noPrice, -amount, popular]
        case "new": return [product.facts.createdRank ?? Int.max]
        default: return [popular]
        }
    }

    private func facets(for products: [DemoProductEntry]) -> ProductFacets {
        var prices: [Int] = []
        var counts: [String: Int] = [:]
        var order: [String] = []
        for product in products {
            if let amount = product.facts.price?.amount, product.facts.price?.onRequest != true, amount > 0 {
                prices.append(amount)
            }
            // «Чёрный»/«Черный» — один пункт фильтра, товар считается один раз.
            var unique: [String] = []
            for color in (product.facts.colors ?? []).map(DemoColorPalette.canonical) where !unique.contains(color) {
                unique.append(color)
            }
            for color in unique {
                if counts[color] == nil { order.append(color) }
                counts[color, default: 0] += 1
            }
        }
        let sortedColors = order.enumerated()
            .sorted { (counts[$0.element] ?? 0, -$0.offset) > (counts[$1.element] ?? 0, -$1.offset) }
            .map { ColorFacet(name: $0.element, hex: DemoColorPalette.hex($0.element), count: counts[$0.element] ?? 0) }
        return ProductFacets(priceMin: prices.min(), priceMax: prices.max(), colors: sortedColors)
    }

    // MARK: - Товары

    func summaries(_ ids: [Int]) -> [ProductSummary] {
        ids.compactMap { data.productsById[$0]?.summary }
    }

    func newest(_ limit: Int) -> [ProductSummary] {
        data.products.enumerated()
            .sorted { ($0.element.facts.createdRank ?? Int.max, $0.offset) < ($1.element.facts.createdRank ?? Int.max, $1.offset) }
            .prefix(limit)
            .map { $0.element.summary }
    }

    func resolve(path: String) -> ResolvePayload? {
        let segments = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard !segments.isEmpty else { return nil }
        let joined = segments.joined(separator: "/")
        for category in data.categories {
            let categoryPath = (category.url.flatMap { URLComponents(string: $0)?.path } ?? "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !categoryPath.isEmpty, categoryPath == joined {
                return ResolvePayload(type: .category, id: category.id, complectId: nil, subId: nil, priceType: nil, url: nil)
            }
        }
        guard let entry = data.products.first(where: { $0.facts.slug == segments[0] }) else { return nil }
        var complectId: Int?
        var subId: String?
        var priceType: String?
        if segments.count > 1 {
            for link in data.product(entry.summary.id)?.variantLinks ?? [] {
                // Слаг варианта — последним сегментом или полным путём «товар/вариант».
                let slug = (link.slug ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if slug == segments[1] || slug == segments[0] + "/" + segments[1] {
                    complectId = link.complectId ?? complectId
                    subId = link.subId ?? subId
                    priceType = link.priceType?.rawValue ?? priceType
                }
            }
        }
        return ResolvePayload(type: .product, id: entry.summary.id, complectId: complectId, subId: subId, priceType: priceType, url: nil)
    }

    // MARK: - Поиск

    func search(_ query: String, offset: Int, limit: Int) -> (products: [ProductSummary], categories: [CategoryNode], total: Int) {
        let words = DemoText.words(query)
        guard !words.isEmpty else { return ([], [], 0) }
        let phrase = words.joined(separator: " ")
        let scored = data.products.enumerated()
            .compactMap { item -> (Int, Int, Int, DemoProductEntry)? in
                let score = Self.score(DemoText.normalize(item.element.facts.name), phrase: phrase, words: words)
                return score > 0 ? (score, item.element.facts.sortPopular ?? 0, item.offset, item.element) : nil
            }
            .sorted { ($1.0, $0.1, $0.2) < ($0.0, $1.1, $1.2) }
        let categories = data.categories
            .filter { Self.score(DemoText.normalize($0.name), phrase: phrase, words: words) >= 50 }
            .prefix(10)
            .map { $0.node() }
        let page = scored.dropFirst(offset).prefix(limit).map { $0.3.summary }
        return (Array(page), Array(categories), scored.count)
    }

    static func score(_ haystack: String, phrase: String, words: [String]) -> Int {
        guard !haystack.isEmpty else { return 0 }
        if haystack.contains(phrase) {
            return 100 + (haystack.hasPrefix(phrase) ? 20 : 0)
        }
        let hits = words.filter { $0.count >= 2 && haystack.contains($0) }.count
        if hits == words.count { return 50 + hits }
        return hits > 0 ? 10 * hits : 0
    }

    // MARK: - Главная

    func home() -> Any {
        guard let raw = data.raw("home.json") as? [String: Any],
              let sections = raw["sections"] as? [[String: Any]] else { return ["sections": [Any]()] }
        let built = sections.map { section -> [String: Any] in
            guard section["type"] as? String == "products" else { return section }
            var copy = section
            let ids = (section["productIds"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
            let products = ids.isEmpty ? newest(10) : summaries(ids)
            copy["products"] = DemoJSON.object(products)
            copy.removeValue(forKey: "productIds")
            return copy
        }
        return ["sections": built]
    }

    // MARK: - Площадки

    func venues(_ query: DemoVenueQuery) -> (items: [VenueSummary], total: Int, counts: [String: [String: Int]]) {
        let matching = data.venues.enumerated()
            .filter { venueMatches($0.element, query, skipGroup: nil) }
            .sorted { ($0.element.facts.sortPopular ?? Int.max, $0.offset) < ($1.element.facts.sortPopular ?? Int.max, $1.offset) }
            .map { $0.element }

        var counts: [String: [String: Int]] = [:]
        for group in ["events", "types", "metro", "props"] {
            var groupCounts: [String: Int] = [:]
            for venue in data.venues where venueMatches(venue, query, skipGroup: group) {
                for id in Self.groupValues(venue.facts, group) {
                    groupCounts[String(id), default: 0] += 1
                }
            }
            counts[group] = groupCounts
        }
        let offset = (query.page - 1) * query.limit
        let page = Array(matching.dropFirst(offset).prefix(query.limit)).map(\.summary)
        return (page, matching.count, counts)
    }

    private static func groupValues(_ facts: DemoVenueFacts, _ group: String) -> [Int] {
        switch group {
        case "events": return facts.events ?? []
        case "types": return facts.types ?? []
        case "metro": return facts.metroIds ?? []
        default: return facts.props ?? []
        }
    }

    private func venueMatches(_ venue: DemoVenueEntry, _ query: DemoVenueQuery, skipGroup: String?) -> Bool {
        let selected: [String: [Int]] = ["events": query.events, "types": query.types, "metro": query.metro, "props": query.props]
        for (group, ids) in selected where group != skipGroup && !ids.isEmpty {
            let values = Set(Self.groupValues(venue.facts, group))
            let ok = group == "props" ? Set(ids).isSubset(of: values) : !values.isDisjoint(with: ids)
            if !ok { return false }
        }
        if let collection = query.collection, !(venue.facts.collections ?? []).contains(collection) {
            return false
        }
        for (key, range) in query.ranges {
            let value: Int?
            switch key {
            case "price": value = venue.facts.priceAmount
            case "capacity": value = venue.facts.capacity
            default: value = venue.facts.area
            }
            guard let value else { return false }
            if let from = range.0, value < from { return false }
            if let to = range.1, value > to { return false }
        }
        return true
    }

    func venueId(slug: String) -> Int? {
        data.venues.first { $0.facts.slug == slug }?.facts.id
    }
}
