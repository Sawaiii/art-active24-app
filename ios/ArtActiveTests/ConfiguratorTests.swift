import XCTest
@testable import ArtActive

/// Логика конфигуратора на фикстурах (стол, плов, батут, мастер-класс).
final class ConfiguratorTests: XCTestCase {
    private func product(_ file: String) throws -> Product {
        try FixtureLoader.decode(Product.self, file: file)
    }

    func testViktoriaDaysAndHint() throws {
        let configurator = Configurator(product: try product("product-viktoria"))
        var state = try XCTUnwrap(configurator.initialState())
        XCTAssertEqual(state.complectId, 1724)
        XCTAssertEqual(state.time, TimeSelection(unit: .days, value: 1))
        XCTAssertEqual(configurator.price(state)?.unitPrice, 770)
        XCTAssertNotNil(configurator.hint(state), "подсказка «с 2-го дня — 154 ₽»")
        XCTAssertTrue(configurator.hint(state)?.contains(Money.rub(154)) == true)

        state = configurator.selectingTime(TimeSelection(unit: .days, value: 2), from: state)
        state = configurator.settingQty(2, from: state)
        let price = try XCTUnwrap(configurator.price(state))
        XCTAssertEqual(price.unitPrice, 924)
        XCTAssertEqual(price.total, 1848)

        let options = try XCTUnwrap(configurator.timeOptions(state))
        XCTAssertEqual(options.primary.count, 7, "1–6 д + «ещё»")
        XCTAssertEqual(options.moreMinimum, 7)

        let input = configurator.cartInput(state)
        XCTAssertEqual(input.complectId, 1724)
        XCTAssertEqual(input.time, TimeSelection(unit: .days, value: 2))
        XCTAssertEqual(input.qty, 2)
    }

    func testComplectChangeKeepsTimeAndResetsExtras() throws {
        let configurator = Configurator(product: try product("product-viktoria"))
        var state = try XCTUnwrap(configurator.initialState())
        state = configurator.selectingTime(TimeSelection(unit: .days, value: 3), from: state)
        state = configurator.togglingExtra("stul-kyavari", from: state)
        XCTAssertEqual(state.extras["stul-kyavari"], 1)

        state = configurator.selectingComplect(1725, from: state)
        XCTAssertEqual(state.time, TimeSelection(unit: .days, value: 3))
        XCTAssertNil(state.extras["stul-kyavari"])
        XCTAssertEqual(configurator.price(state)?.unitPrice, 2156) // 1540 × 1.4
    }

    func testPlovSubsAndMinimum() throws {
        let configurator = Configurator(product: try product("product-plov"))
        let state = try XCTUnwrap(configurator.initialState())
        XCTAssertEqual(state.subId, "1591")
        XCTAssertEqual(state.qty, 10, "минимум порций берётся из варианта")
        XCTAssertNil(configurator.timeOptions(state), "sale — время скрыто")
        XCTAssertEqual(configurator.subGroups(state).map(\.title), ["Привозим готовое", "Готовим на месте", "Мастер класс"])
        XCTAssertEqual(configurator.price(state)?.total, 3400)

        var withCook = configurator.togglingExtra("povar", from: state)
        withCook = configurator.settingQty(20, from: withCook)
        XCTAssertEqual(configurator.price(withCook)?.total, 20 * 340 + 8500, "доп — один раз, не × кол-во")
        XCTAssertEqual(configurator.qtyUnit(state), "порц.")
    }

    func testTrampolineRequiredExtraAndBuyMode() throws {
        let configurator = Configurator(product: try product("product-batut"))
        var state = try XCTUnwrap(configurator.initialState())
        XCTAssertEqual(configurator.mode, .trampoline)
        XCTAssertEqual(state.extras["bariery"], 1, "обязательный доп предвыбран")
        XCTAssertEqual(configurator.togglingExtra("bariery", from: state).extras["bariery"], 1, "обязательный не снимается")

        state = configurator.selectingSub("tramp-asphalt-0", from: state)
        state = configurator.selectingTime(TimeSelection(unit: .hours, value: 7), from: state)
        XCTAssertEqual(configurator.price(state)?.unitPrice, 81500)
        XCTAssertEqual(configurator.price(state)?.total, 93500)

        state = configurator.selectingPriceType(.buy, from: state)
        XCTAssertFalse(configurator.showsSubs(state))
        XCTAssertNil(configurator.activeTimeRule(state))
        XCTAssertEqual(configurator.price(state)?.unitPrice, 1_260_000)
        XCTAssertEqual(configurator.shareURL(state)?.absoluteString, "https://www.art-active24.ru/batut-korabl-bolshoj/kupit-batut-korabl/")
    }

    func testMasterclassBadgeAndNoTime() throws {
        let configurator = Configurator(product: try product("product-masterclass"))
        let state = try XCTUnwrap(configurator.initialState())
        XCTAssertEqual(configurator.mode, .masterclass)
        XCTAssertEqual(configurator.badge(state), "за 10 участников")
        XCTAssertNil(configurator.timeOptions(state))
        XCTAssertTrue(configurator.plainExtras.isEmpty)
        XCTAssertEqual(configurator.price(state)?.total, 9000)
    }

    func testCateringMenuValidation() throws {
        let complect = Complect(
            id: 1, title: "Боксы", subtitle: nil, textHtml: nil, image: nil, pdfUrl: nil,
            rent: PriceSide(amount: 0, label: "Стоимость"), buy: nil, time: nil, basePrice: 5000, basePriceName: "Выезд",
            subsLabel: nil, subs: nil,
            menu: [MenuRow(id: "m1", group: nil, name: "Канапе", price: 100, minQty: 20)],
            reward: nil, includes: nil, requirements: nil, comment: nil
        )
        let product = Product(
            id: 1, slug: "box", art: nil, name: "Боксы", template: .configurator, configuratorMode: .cateringMenu,
            orderMode: .cart, categoryId: nil, breadcrumbs: nil, badge: nil, image: nil, media: [], price: nil, lead: nil,
            specs: nil, descriptionHtml: nil, complectsLabel: nil, complects: [complect], extras: [],
            similar: nil, variantLinks: nil, masterclass: nil, blocks: nil, shareUrl: nil
        )
        let configurator = Configurator(product: product)
        var state = try XCTUnwrap(configurator.initialState())
        XCTAssertTrue(state.menu.isEmpty)

        state = configurator.settingMenuQty("m1", qty: 1, from: state)
        XCTAssertEqual(state.menu["m1"], 20, "первый шаг — сразу к минимуму")
        XCTAssertNil(configurator.validationError(state))
        XCTAssertEqual(configurator.price(state)?.total, 2000 + 5000)

        state = configurator.settingMenuQty("m1", qty: 19, from: state)
        XCTAssertNil(state.menu["m1"], "шаг ниже минимума снимает строку")
    }

    func testUnitWord() {
        XCTAssertEqual(Configurator.unitWord(from: "/ порц."), "порц.")
        XCTAssertNil(Configurator.unitWord(from: "/ 40 л."), "постфикс-вместимость — не единица")
        XCTAssertNil(Configurator.unitWord(from: "/ до 40 чел"))
        XCTAssertEqual(Configurator.unitWord(from: "за участника"), "участника")
        XCTAssertNil(Configurator.unitWord(from: nil))
    }
}
