import XCTest
@testable import ArtActive

/// Каждая встроенная карточка товара и площадки разбирается тем же декодером, что и приложение.
/// Иначе на устройстве такая карточка открывается ошибкой.
final class DemoDatasetDecodingTests: XCTestCase {
    private func datasetDirectory() throws -> URL {
        for name in ["DemoData", "demo"] {
            if let url = Bundle.main.url(forResource: name, withExtension: nil) { return url }
        }
        throw XCTSkip("Набор DemoData не встроен в бандл")
    }

    func testEveryListedProductHasDecodableCard() throws {
        let dir = try datasetDirectory()
        let decoder = JSONCoding.makeDecoder()
        let summaries = try decoder.decode([ProductSummary].self, from: Data(contentsOf: dir.appendingPathComponent("products.json")))
        XCTAssertFalse(summaries.isEmpty)

        var failures: [String] = []
        for summary in summaries {
            let file = dir.appendingPathComponent("products/\(summary.id).json")
            guard let data = try? Data(contentsOf: file) else {
                failures.append("\(summary.id) \(summary.slug): нет файла карточки")
                continue
            }
            do {
                let product = try decoder.decode(Product.self, from: data)
                XCTAssertEqual(product.id, summary.id)
            } catch {
                failures.append("\(summary.id) \(summary.slug): \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Карточки не разбираются (\(failures.count)):\n" + failures.prefix(15).joined(separator: "\n"))
    }

    func testEveryListedCaseHasDecodableCard() throws {
        let dir = try datasetDirectory()
        let listFile = dir.appendingPathComponent("cases.json")
        guard FileManager.default.fileExists(atPath: listFile.path) else { throw XCTSkip("В наборе ещё нет кейсов") }
        let decoder = JSONCoding.makeDecoder()
        let list = try decoder.decode(CaseListPayload.self, from: Data(contentsOf: listFile))

        var failures: [String] = []
        for item in list.items ?? [] {
            let file = dir.appendingPathComponent("cases/\(item.slug).json")
            guard let data = try? Data(contentsOf: file) else {
                failures.append("\(item.slug): нет файла карточки")
                continue
            }
            do {
                let study = try decoder.decode(CaseStudy.self, from: data)
                XCTAssertEqual(study.slug, item.slug)
            } catch {
                failures.append("\(item.slug): \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Кейсы не разбираются (\(failures.count)):\n" + failures.prefix(15).joined(separator: "\n"))
    }

    func testEveryListedVenueHasDecodableCard() throws {
        let dir = try datasetDirectory()
        let decoder = JSONCoding.makeDecoder()
        let venues = try decoder.decode([VenueSummary].self, from: Data(contentsOf: dir.appendingPathComponent("venues.json")))

        var failures: [String] = []
        for venue in venues {
            let file = dir.appendingPathComponent("venues/\(venue.id).json")
            guard let data = try? Data(contentsOf: file) else {
                failures.append("\(venue.id): нет файла карточки")
                continue
            }
            do {
                _ = try decoder.decode(Venue.self, from: data)
            } catch {
                failures.append("\(venue.id): \(error)")
            }
        }
        XCTAssertTrue(failures.isEmpty, "Площадки не разбираются (\(failures.count)):\n" + failures.prefix(15).joined(separator: "\n"))
    }
}
