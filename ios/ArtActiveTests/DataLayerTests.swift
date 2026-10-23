import XCTest
@testable import ArtActive

/// Загрузка фикстур из папки Fixtures тест-бандла.
enum FixtureLoader {
    static func decode<T: Decodable>(_ type: T.Type, file: String) throws -> T {
        let bundle = Bundle(for: DataLayerTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: file, withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: file, withExtension: "json"),
            "Нет фикстуры \(file).json"
        )
        return try JSONCoding.makeDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

/// DTO точно по контракту: фикстуры превью декодируются, неизвестные enum не роняют разбор.
final class DataLayerTests: XCTestCase {
    func testProductFixturesDecode() throws {
        for file in ["product-viktoria", "product-plov", "product-batut", "product-masterclass"] {
            let product = try FixtureLoader.decode(Product.self, file: file)
            XCTAssertFalse(product.complects.isEmpty, file)
            XCTAssertEqual(product.template, .configurator, file)
        }
        let viktoria = try FixtureLoader.decode(Product.self, file: "product-viktoria")
        XCTAssertEqual(viktoria.complects.count, 5)
        XCTAssertEqual(viktoria.complects.first?.time?.defaultValue, 1)
    }

    func testCatalogFixtureDecodes() throws {
        let catalog = try FixtureLoader.decode(PreviewFixtures.Catalog.self, file: "catalog")
        XCTAssertFalse(catalog.home.sections?.isEmpty ?? true)
        XCTAssertEqual(catalog.order.status, .confirmed)
        XCTAssertEqual(catalog.order.history.count, 2)
        XCTAssertNotNil(catalog.order.history.last?.at)
        XCTAssertEqual(catalog.venueFilters.ranges?["price"]?.max, 166_666)
    }

    func testVenueFixtureDecodes() throws {
        let venue = try FixtureLoader.decode(Venue.self, file: "venue")
        XCTAssertEqual(venue.metro?.first?.color, "#A2A5B4")
        XCTAssertEqual(venue.geo?.lat ?? 0, 55.8065, accuracy: 0.0001)
    }

    func testUnknownEnumValuesDoNotBreakDecoding() throws {
        let json = #"{"id":1,"slug":"x","name":"X","template":"brand-new-template"}"#
        let summary = try JSONCoding.makeDecoder().decode(ProductSummary.self, from: Data(json.utf8))
        XCTAssertEqual(summary.template, .unknown)

        let status = try JSONCoding.makeDecoder().decode([OrderStatus].self, from: Data(#"["in_progress","archived"]"#.utf8))
        XCTAssertEqual(status, [.inProgress, .unknown])
    }

    func testOmittedOptionalKeys() throws {
        // API не отдаёт null — пустые ключи опускаются.
        let json = #"{"lines":[],"total":0}"#
        let quote = try JSONCoding.makeDecoder().decode(Quote.self, from: Data(json.utf8))
        XCTAssertNil(quote.hasOnRequest)
        XCTAssertNil(quote.count)
    }

    func testCartItemEncodingOmitsNil() throws {
        let item = CartItemInput(productId: 7138, complectId: 1724, priceType: .rent, qty: 2)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONCoding.encode(item)) as? [String: Any])
        XCTAssertEqual(object["productId"] as? Int, 7138)
        XCTAssertEqual(object["priceType"] as? String, "rent")
        XCTAssertNil(object["subId"])
        XCTAssertNil(object["time"])
    }

    func testDates() {
        XCTAssertNotNil(ISODate.parse("2026-10-14T09:30:00Z"))
        XCTAssertNotNil(ISODate.parse("2026-10-15T12:00:00.000Z"))
        let day = DayDate.date(from: "2026-10-25")
        XCTAssertEqual(day.map(DayDate.string(from:)), "2026-10-25")
    }

    func testPhoneFormatter() {
        XCTAssertEqual(PhoneFormatter.masked("9991234567"), "+7 (999) 123-45-67")
        XCTAssertEqual(PhoneFormatter.masked("+7 (999"), "+7 (999")
        XCTAssertEqual(PhoneFormatter.e164("8 999 123 45 67"), "+79991234567")
        XCTAssertTrue(PhoneFormatter.isMobile("+7 (999) 123-45-67"))
        XCTAssertFalse(PhoneFormatter.isMobile("+7 (495) 032-67-50"))
        XCTAssertTrue(PhoneFormatter.isValid("+7 (495) 032-67-50"), "городской допустим для контактов заказа")
        XCTAssertNil(PhoneFormatter.e164("+7 (999) 12"))
    }

    func testRemoteAPIConfigParsesDirectAndGistFormats() {
        let direct = Data(#"{"apiBaseURL":"https://a.example/"}"#.utf8)
        XCTAssertEqual(APIBaseURLStore.extractBaseURL(from: direct), "https://a.example/")

        let gist = Data(#"{"files":{"api.json":{"content":"{\"apiBaseURL\": \"https://b.example/\"}"}}}"#.utf8)
        XCTAssertEqual(APIBaseURLStore.extractBaseURL(from: gist), "https://b.example/")

        XCTAssertNil(APIBaseURLStore.extractBaseURL(from: Data("not json".utf8)))
        XCTAssertNotNil(APIBaseURLStore.validURL("https://x.example/"))
        XCTAssertNil(APIBaseURLStore.validURL("http://x.example/"), "только HTTPS")
        XCTAssertNil(APIBaseURLStore.validURL(""))
    }

    func testEntityDecodingIsSinglePass() {
        XCTAssertEqual(HTMLParser.decodeEntities("&amp;lt;b&amp;gt;"), "&lt;b&gt;", "без двойного декодирования")
        XCTAssertEqual(HTMLParser.decodeEntities("&#171;&#x00BB; 5&nbsp;₽"), "«» 5\u{00A0}₽")
        XCTAssertEqual(HTMLParser.decodeEntities("&laquoСтол&raquo"), "«Стол»", "сущности сайта без «;»")
        XCTAssertEqual(HTMLParser.decodeEntities("A & B &unknown; C"), "A & B &unknown; C")
    }

    func testHTMLParser() {
        let blocks = HTMLParser.parse("<p>Привет, <strong>мир</strong>&nbsp;&laquo;да&raquo;</p><ul><li>Один</li><li>Два</li></ul>")
        XCTAssertEqual(blocks.count, 3)
        if case let .paragraph(text) = blocks[0] {
            XCTAssertEqual(String(text.characters), "Привет, мир\u{00A0}«да»")
        } else {
            XCTFail("первый блок — абзац")
        }
        if case let .listItem(marker, text) = blocks[2] {
            XCTAssertEqual(marker, "•")
            XCTAssertEqual(String(text.characters), "Два")
        } else {
            XCTFail("третий блок — пункт списка")
        }
    }

    func testVenueQueryItems() {
        var query = VenueQuery(collection: 900_002)
        query.events = [4, 2]
        query.priceTo = 10_000
        let items = Dictionary(uniqueKeysWithValues: query.queryItems.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["events"], "2,4")
        XCTAssertEqual(items["priceTo"], "10000")
        XCTAssertEqual(items["collection"], "900002")
        XCTAssertNil(items["metro"])
    }
}
