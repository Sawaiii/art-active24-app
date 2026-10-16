import XCTest
@testable import ArtActive

/// Прогоняет ВСЕ эталонные векторы `contract/pricing-vectors.json` (общие для PHP, Kotlin и Swift).
/// Файл подключён ресурсом тест-таргета прямо из contract/ (см. project.yml).
final class PricingVectorTests: XCTestCase {
    private struct VectorFile: Decodable {
        let vectors: [Vector]
    }

    private struct Vector: Decodable {
        let name: String
        let complect: VectorComplect
        let extras: [Extra]?
        let input: VectorInput
        let expect: VectorExpect
    }

    /// Комплект в векторах — без id/title (они не влияют на цену).
    private struct VectorComplect: Decodable {
        let rent: PriceSide?
        let buy: PriceSide?
        let time: TimeRule?
        let basePrice: Int?
        let subs: [Sub]?
        let menu: [MenuRow]?
        let reward: Reward?

        var complect: Complect {
            Complect(
                id: 0, title: "vector", subtitle: nil, textHtml: nil, image: nil, pdfUrl: nil,
                rent: rent, buy: buy, time: time, basePrice: basePrice, basePriceName: nil, subsLabel: nil,
                subs: subs, menu: menu, reward: reward, includes: nil, requirements: nil, comment: nil
            )
        }
    }

    private struct VectorInput: Decodable {
        let priceType: PriceType?
        let subId: String?
        let time: TimeSelection?
        let qty: Int?
        let extras: [ExtraSelection]?
        let menu: [MenuSelection]?

        var pricingInput: PricingInput {
            PricingInput(
                priceType: priceType ?? .rent,
                subId: subId,
                time: time,
                qty: qty ?? 1,
                extras: extras ?? [],
                menu: menu ?? []
            )
        }
    }

    private struct VectorExpect: Decodable {
        let unitPrice: Int?
        let total: Int?
        let timeLabel: String?
        let onRequest: Bool?
        let error: String?
    }

    private func loadVectors() throws -> [Vector] {
        let bundle = Bundle(for: PricingVectorTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "pricing-vectors", withExtension: "json"),
            "pricing-vectors.json не подключён к тест-таргету"
        )
        return try JSONCoding.makeDecoder().decode(VectorFile.self, from: Data(contentsOf: url)).vectors
    }

    func testContractHasAllVectors() throws {
        XCTAssertGreaterThanOrEqual(try loadVectors().count, 23, "В контракте 23+ векторов — файл обрезан?")
    }

    func testAllPricingVectors() throws {
        let vectors = try loadVectors()
        var checked = 0
        for vector in vectors {
            let complect = vector.complect.complect
            let extras = vector.extras ?? []
            let input = vector.input.pricingInput

            if let field = vector.expect.error {
                XCTAssertThrowsError(try Pricing.calculate(complect: complect, extras: extras, input: input), vector.name) { error in
                    XCTAssertEqual((error as? PricingError)?.field, field, "\(vector.name): поле ошибки")
                }
                checked += 1
                continue
            }

            do {
                let result = try Pricing.calculate(complect: complect, extras: extras, input: input)
                if let unit = vector.expect.unitPrice {
                    XCTAssertEqual(result.unitPrice, unit, "\(vector.name): unitPrice")
                }
                if let total = vector.expect.total {
                    XCTAssertEqual(result.total, total, "\(vector.name): total")
                }
                XCTAssertEqual(result.timeLabel, vector.expect.timeLabel, "\(vector.name): timeLabel")
                XCTAssertEqual(result.onRequest, vector.expect.onRequest ?? false, "\(vector.name): onRequest")
            } catch {
                XCTFail("\(vector.name): неожиданная ошибка \(error)")
            }
            checked += 1
        }
        XCTAssertEqual(checked, vectors.count)
    }

    func testRoundingFollowsContract() {
        // floor(x + 0.5 + 1e-9)
        XCTAssertEqual(Pricing.roundRub(1105.5), 1106)
        XCTAssertEqual(Pricing.roundRub(923.9999999999), 924)
        XCTAssertEqual(Pricing.roundRub(71500.16), 71500)
        XCTAssertEqual(Pricing.roundRub(0.49), 0)
    }

    func testOptionLineWithoutComplect() throws {
        let extras = [
            Extra(id: "barmen", name: "Бармен", price: 8000, from: nil, image: nil, group: nil, required: nil, note: nil, countable: nil),
            Extra(id: "bariery", name: "Барьеры", price: 12000, from: nil, image: nil, group: nil, required: true, note: nil, countable: nil),
        ]
        let result = try Pricing.optionLine(extras: extras, selected: [ExtraSelection(id: "barmen")], qty: 2)
        XCTAssertEqual(result.unitPrice, 8000, "обязательные допы в строку-опцию не добавляются")
        XCTAssertEqual(result.total, 16000)
        XCTAssertThrowsError(try Pricing.optionLine(extras: extras, selected: [], qty: 1)) { error in
            XCTAssertEqual((error as? PricingError)?.field, "extras")
        }
        let line = CartItemInput.option(productId: 1, extraIds: ["barmen"])
        XCTAssertNil(line.complectId)
        XCTAssertNotEqual(line.lineKey, CartItemInput.option(productId: 1, extraIds: ["other"]).lineKey)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONCoding.encode(line)) as? [String: Any])
        XCTAssertNil(object["complectId"], "без complectId ключ опускается")
    }

    func testRequiredExtraAlwaysIncluded() {
        let extras = [Extra(id: "bariery", name: "Барьеры", price: 12000, from: nil, image: nil, group: nil, required: true, note: nil, countable: nil)]
        XCTAssertEqual(Pricing.extrasSum(extras: extras, selected: []), 12000)
        XCTAssertEqual(Pricing.extrasSum(extras: extras, selected: [ExtraSelection(id: "bariery")]), 12000)
    }
}
