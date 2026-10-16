import XCTest

/// Сценарий скриншотов всех ключевых экранов для визуальной проверки (workflow ios-screenshots.yml).
///
/// Это не проверка поведения: каждый шаг «мягкий» — если элемент не нашёлся, в лог пишется
/// предупреждение, снимок всё равно делается, сценарий идёт дальше. Данные — демо-датасет
/// API (api/tests/fixtures/demo) на 127.0.0.1:8080; вход — review-номер с постоянным кодом.
///
/// Снимки: `NN-name.png` в каталоге из `SCREENSHOTS_DIR` (в xcodebuild передаётся как
/// `TEST_RUNNER_SCREENSHOTS_DIR`) и вложениями в .xcresult. Методы выполняются по алфавиту,
/// состояние (корзина, вход) переживает перезапуски приложения.
final class ScreenshotTests: XCTestCase {
    private enum Tab: Int {
        case home = 0, catalog, cart, favorites, profile

        var label: String {
            switch self {
            case .home: return "Главная"
            case .catalog: return "Каталог"
            case .cart: return "Корзина"
            case .favorites: return "Избранное"
            case .profile: return "Профиль"
            }
        }
    }

    private enum ProductID {
        static let viktoria = 7138
        static let plov = 469
        static let batut = 763
        static let akvagrim = 721
        static let cateringBox = 2083
        static let teaStation = 1055
        static let sodaMachine = 6152
        static let hostess = 3344
        static let teambuilding = 7011
        static let catchMoment = 10191
    }

    private static let reviewPhoneDigits = "9005553535"
    private static let reviewCode = "424242"
    private static let tablesCategoryId = 225
    private static let furnitureCategoryId = 257
    private static let venuesCategoryId = 676

    // MARK: - Главная

    @MainActor
    func test01_HomeRussian() {
        let app = launch()
        waitForAny(app, ids: ["home.search"], timeout: 20)
        snap("01-home-top", settle: 4)
        drag(app, times: 2)
        snap("02-home-directions")
        drag(app, times: 3)
        snap("03-home-novelties")
        drag(app, times: 4)
        snap("04-home-bottom")
    }

    @MainActor
    func test02_HomeEnglish() {
        let app = launch(language: "en")
        waitForAny(app, ids: ["home.search"], timeout: 20)
        snap("05-home-en-top", settle: 4)
        drag(app, times: 3)
        snap("06-home-en-scrolled")
    }

    @MainActor
    func test03_HomeDark() {
        let app = launch(appearance: "dark")
        waitForAny(app, ids: ["home.search"], timeout: 20)
        snap("07-home-dark", settle: 4)
        drag(app, times: 3)
        snap("08-home-dark-scrolled")
    }

    // MARK: - Каталог → Мебель → Столы

    @MainActor
    func test10_CatalogToTables() {
        let app = launch()
        openTab(app, .catalog)
        snap("09-catalog-l1", settle: 3)

        tapId(app, "catalog.node.\(Self.furnitureCategoryId)")
        snap("10-catalog-l2-furniture")

        tapId(app, "catalog.node.\(Self.tablesCategoryId)")
        // У «Столов» есть подразделы → экран уровня 3 с «Все: Столы»; иначе сразу раздел.
        if element(app, "catalog.all").waitForExistence(timeout: 4) {
            snap("11-catalog-l3-tables")
            tapId(app, "catalog.all")
        }
        waitForPrefix(app, "product.tile.", timeout: 15)
        snap("12-category-tables", settle: 3)
        drag(app, times: 3)
        snap("13-category-tables-grid", settle: 3)
        drag(app, times: 3, up: false)

        if tapId(app, "category.filter") {
            snap("14-category-filter-sheet")
            if !tapId(app, "filter.apply", timeout: 3, scroll: false) { app.swipeDown() }
            pause(1.5)
        }

        if tapId(app, "category.sort", scroll: false) {
            let cheaper = app.buttons["Сначала дешевле"].firstMatch
            // Picker внутри Menu может отрисоваться вложенным подменю «Сортировка».
            if !cheaper.waitForExistence(timeout: 2) {
                // Первая «Сортировка» — сама кнопка тулбара, пункт подменю — последний.
                let candidates = app.buttons.matching(NSPredicate(format: "label == %@", "Сортировка"))
                if candidates.count > 1 { candidates.element(boundBy: candidates.count - 1).tap() }
            }
            snap("15-category-sort-menu", settle: 1.5)
            if cheaper.waitForExistence(timeout: 3) {
                cheaper.tap()
                waitForPrefix(app, "product.tile.", timeout: 10)
                snap("16-category-sorted-price", settle: 3)
            } else {
                note("нет пункта сортировки «Сначала дешевле»")
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
            }
        }
    }

    @MainActor
    func test11_CategoryDark() {
        let app = launch(appearance: "dark", deepLink: "artactive24://category/\(Self.tablesCategoryId)")
        waitForPrefix(app, "product.tile.", timeout: 20)
        snap("17-category-tables-dark", settle: 3)
    }

    // MARK: - Поиск

    @MainActor
    func test20_SearchTrampoline() {
        let app = launch()
        guard tapId(app, "home.search", timeout: 20, scroll: false) else { return snap("18-search-failed") }
        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 8) else {
            note("нет поля поиска")
            return snap("18-search-empty")
        }
        snap("18-search-suggestions", settle: 1.5)
        field.tap()
        field.typeText("батут")
        waitForPrefix(app, "product.tile.", timeout: 15)
        pause(1)
        // Скрываем клавиатуру прокруткой результатов (scrollDismissesKeyboard).
        drag(app, times: 1, up: false)
        snap("19-search-trampoline", settle: 3)
        drag(app, times: 3)
        snap("20-search-trampoline-more", settle: 2)
    }

    // MARK: - Карточки

    /// Стол «Виктория 180»: комплекты + дни, липкий бар, «Итого», все комплекты, галерея.
    @MainActor
    func test30_CardTableViktoria() {
        let app = openProduct(ProductID.viktoria)
        snap("21-card-viktoria", settle: 3)

        tapId(app, "config.complect.1725")
        if !tapId(app, "time.days-3", timeout: 4) { tapId(app, "time.days-2", timeout: 2) }
        snap("22-card-viktoria-complect-days")

        if tapId(app, "cartbar.add", scroll: false) { snap("23-card-viktoria-in-cart") }

        if tapId(app, "cartbar.total", scroll: false) {
            snap("24-card-viktoria-total-breakdown")
            if !tapId(app, "breakdown.done", timeout: 3, scroll: false) { app.swipeDown() }
            pause(1)
        }

        if tapId(app, "config.complects.all") {
            snap("25-card-viktoria-all-complects")
            dismissSheet(app)
        }

        drag(app, times: 4)
        snap("26-card-viktoria-specs-description")
        drag(app, times: 4)
        snap("27-card-viktoria-similar")

        drag(app, times: 12, up: false)
        if tapId(app, "gallery.item") {
            snap("28-gallery-fullscreen", settle: 3)
            app.swipeLeft()
            snap("29-gallery-fullscreen-next", settle: 2)
            if !tapId(app, "gallery.close", timeout: 3, scroll: false) { app.swipeDown() }
        }
    }

    @MainActor
    func test31_CardTableViktoriaDark() {
        _ = openProduct(ProductID.viktoria, appearance: "dark")
        snap("30-card-viktoria-dark", settle: 3)
    }

    /// Плов: комплекты, варианты (subs), доп. опции, в корзину.
    @MainActor
    func test32_CardPlov() {
        let app = openProduct(ProductID.plov)
        snap("31-card-plov", settle: 3)

        tapId(app, "config.complect.483")
        let subs = byPrefix(app, "config.sub.")
        if subs.count > 1 {
            let second = subs.element(boundBy: 1)
            if reveal(second, in: app) { second.tap() }
        }
        snap("32-card-plov-variants")

        let extra = byPrefix(app, "config.extra.").firstMatch
        if reveal(extra, in: app) {
            extra.tap()
            snap("33-card-plov-extras")
        } else {
            note("у плова не нашлись доп. опции")
        }
        if tapId(app, "cartbar.add", scroll: false) { snap("34-card-plov-in-cart") }
    }

    /// Батут: способ установки, аренда/покупка.
    @MainActor
    func test33_CardTrampoline() {
        let app = openProduct(ProductID.batut)
        snap("35-card-trampoline", settle: 3)

        let install = byPrefix(app, "config.sub.")
        if install.count > 1 {
            let second = install.element(boundBy: 1)
            if reveal(second, in: app) { second.tap() }
        }
        snap("36-card-trampoline-install")

        let format = app.segmentedControls["config.priceType"].firstMatch
        let segmented = format.exists ? format : app.segmentedControls.firstMatch
        if reveal(segmented, in: app, maxSwipes: 4, up: false), segmented.buttons.count > 1 {
            segmented.buttons.element(boundBy: 1).tap()
            snap("37-card-trampoline-buy")
        } else {
            note("нет переключателя «Аренда/Купить»")
        }
    }

    /// Мастер-класс «Аквагрим»: площадки (модалка), вкладки «Как проходит / Что включено».
    @MainActor
    func test34_CardMasterclass() {
        let app = openProduct(ProductID.akvagrim)
        snap("38-card-masterclass", settle: 3)

        if tapId(app, "mk.venues") {
            snap("39-card-masterclass-venues", settle: 3)
            if !tapId(app, "mk.venues.done", timeout: 3, scroll: false) { dismissSheet(app) }
            pause(1)
        }

        let included = app.buttons["Что включено"].firstMatch
        if reveal(included, in: app, maxSwipes: 10) {
            snap("40-card-masterclass-steps")
            included.tap()
            snap("41-card-masterclass-included")
        } else {
            drag(app, times: 4)
            snap("40-card-masterclass-info")
        }
        drag(app, times: 4)
        snap("42-card-masterclass-related")
    }

    /// Кейтеринг-меню (фуршетный бокс): состав заказа, шкала бонуса.
    @MainActor
    func test35_CardCateringMenu() {
        let app = openProduct(ProductID.cateringBox)
        snap("43-card-catering", settle: 3)
        let add = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Добавить ")).firstMatch
        if reveal(add, in: app) {
            add.tap()
            pause(0.5)
        }
        snap("44-card-catering-menu")
    }

    /// Шаблон «простая» (чайный уголок): комплекты-тумблеры, кладём в корзину.
    @MainActor
    func test36_CardSimpleTeaStation() {
        let app = openProduct(ProductID.teaStation)
        snap("45-card-simple-tea", settle: 3)
        let toggle = byPrefix(app, "toggle.complect.").firstMatch
        if reveal(toggle, in: app) {
            toggle.tap()
            snap("46-card-simple-in-cart")
        } else {
            note("нет кнопки «В корзину» у комплекта")
        }
        drag(app, times: 4)
        snap("47-card-simple-extras")
    }

    /// Шаблон «сложная» (автомат газ. воды): промо-шапка, контент-блоки.
    @MainActor
    func test37_CardShowcase() {
        let app = openProduct(ProductID.sodaMachine, waitFor: [])
        snap("48-card-showcase", settle: 4)
        drag(app, times: 3)
        snap("49-card-showcase-blocks")
        drag(app, times: 4)
        snap("50-card-showcase-complects")
    }

    /// Шаблон «персонал» (хостес).
    @MainActor
    func test38_CardStaff() {
        let app = openProduct(ProductID.hostess)
        snap("51-card-staff", settle: 3)
        drag(app, times: 3)
        snap("52-card-staff-more")
    }

    /// Шаблон «Тимбилдинг 2.0» (программа).
    @MainActor
    func test39_CardProgram() {
        let app = openProduct(ProductID.teambuilding, waitFor: [])
        snap("53-card-program", settle: 4)
        drag(app, times: 3)
        snap("54-card-program-blocks")
        drag(app, times: 4)
        snap("55-card-program-tariffs")
    }

    @MainActor
    func test40_CardCatchMoment() {
        _ = openProduct(ProductID.catchMoment)
        snap("56-card-catch-moment", settle: 3)
    }

    // MARK: - Корзина → вход → оформление → профиль → заказы

    @MainActor
    func test50_CartDark() {
        let app = launch(appearance: "dark")
        openTab(app, .cart)
        snap("57-cart-dark", settle: 3)
    }

    @MainActor
    func test51_CartLoginCheckoutOrders() {
        let app = launch()
        openTab(app, .cart)
        snap("58-cart", settle: 3)
        drag(app, times: 3)
        snap("59-cart-summary", settle: 2)

        guard tapId(app, "cart.checkout") else {
            note("нет кнопки «Оставить заявку» — корзина пуста?")
            return openProfileAndOrders(app)
        }

        // Вход: телефон → код (review-номер, постоянный код).
        // Поле телефона есть и в оформлении — ориентируемся на кнопку «Получить код» шита входа.
        let phone = app.textFields["phone.field"].firstMatch
        if element(app, "login.request").waitForExistence(timeout: 8), phone.waitForExistence(timeout: 3) {
            snap("60-login-phone", settle: 1.5)
            phone.tap()
            phone.typeText(Self.reviewPhoneDigits)
            snap("61-login-phone-filled", settle: 1)
            tapId(app, "login.request", scroll: false)
            let code = app.textFields["login.code"].firstMatch
            if code.waitForExistence(timeout: 10) {
                snap("62-login-code", settle: 1.5)
                code.tap()
                code.typeText(Self.reviewCode)
            } else {
                note("не появился шаг ввода кода")
                snap("62-login-error")
            }
        } else {
            note("шит входа не появился (уже вошли?)")
        }

        // Оформление.
        if element(app, "checkout.submit").waitForExistence(timeout: 15) {
            snap("63-checkout", settle: 2)
            let delivery = app.segmentedControls["checkout.delivery"].firstMatch
            let pickup = delivery.exists ? delivery.buttons.element(boundBy: 1) : app.buttons["Самовывоз"].firstMatch
            if pickup.waitForExistence(timeout: 3) { pickup.tap() }
            drag(app, times: 4)
            snap("64-checkout-bottom")
            if tapId(app, "checkout.submit") {
                snap("65-checkout-success", settle: 4)
            }
        } else {
            note("экран оформления не открылся")
            snap("63-checkout-missing")
        }

        openProfileAndOrders(app)
    }

    @MainActor
    private func openProfileAndOrders(_ app: XCUIApplication) {
        openTab(app, .profile)
        pause(1)
        openTab(app, .profile) // повторный тап — назад к корню профиля
        snap("66-profile", settle: 3)

        guard tapId(app, "profile.orders") else { return }
        waitForPrefix(app, "order.", timeout: 10)
        snap("67-orders", settle: 2)

        // Заявка №1 — корзинная из сида CI, переведена менеджером в «Подтверждён».
        let seeded = element(app, "order.1")
        let target = seeded.waitForExistence(timeout: 3) ? seeded : byPrefix(app, "order.").firstMatch
        if reveal(target, in: app) {
            target.tap()
            snap("68-order-detail", settle: 3)
            drag(app, times: 3)
            snap("69-order-detail-timeline")
            drag(app, times: 4)
            snap("70-order-detail-bottom")
        }
    }

    // MARK: - Площадки

    @MainActor
    func test60_Venues() {
        let app = launch()
        openTab(app, .catalog)
        guard tapId(app, "catalog.node.\(Self.venuesCategoryId)") else { return snap("71-venues-missing") }
        waitForPrefix(app, "venue.card.", timeout: 15)
        snap("71-venues", settle: 4)
        drag(app, times: 3)
        snap("72-venues-scrolled", settle: 3)
        drag(app, times: 6, up: false)

        if tapId(app, "venues.filter") {
            snap("73-venues-filter", settle: 2)
            drag(app, times: 2)
            snap("74-venues-filter-more")
            if !tapId(app, "venuefilter.apply", timeout: 3, scroll: false) { dismissSheet(app) }
            pause(1.5)
        }

        let card = byPrefix(app, "venue.card.").firstMatch
        if reveal(card, in: app) {
            card.tap()
            snap("75-venue-detail", settle: 4)
            drag(app, times: 3)
            snap("76-venue-detail-info")
            drag(app, times: 5)
            snap("77-venue-detail-bottom")
        }
    }

    // MARK: - Запуск и навигация

    @MainActor
    private func launch(language: String = "ru", appearance: String = "light", deepLink: String? = nil) -> XCUIApplication {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITests", "YES",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ru" ? "ru_RU" : "en_US",
        ]
        app.launchEnvironment["UITEST_APPEARANCE"] = appearance
        if let deepLink {
            app.launchEnvironment["UITEST_DEEPLINK"] = deepLink
        }
        app.launch()
        pause(2)
        return app
    }

    /// Карточка по deep link `artactive24://product/{id}` (пушится в стек «Главной»).
    @MainActor
    private func openProduct(_ id: Int, appearance: String = "light", waitFor ids: [String] = ["gallery.item", "cartbar.total"]) -> XCUIApplication {
        let app = launch(appearance: appearance, deepLink: "artactive24://product/\(id)")
        if !ids.isEmpty { waitForAny(app, ids: ids, timeout: 20) } else { pause(4) }
        return app
    }

    @MainActor
    private func openTab(_ app: XCUIApplication, _ tab: Tab) {
        let bar = app.tabBars.firstMatch
        if bar.waitForExistence(timeout: 10) {
            let byLabel = bar.buttons[tab.label].firstMatch
            if byLabel.exists {
                byLabel.tap()
                return pause(1.5)
            }
            if bar.buttons.count > tab.rawValue {
                bar.buttons.element(boundBy: tab.rawValue).tap()
                return pause(1.5)
            }
        }
        let fallback = app.buttons[tab.label].firstMatch
        if fallback.waitForExistence(timeout: 3) {
            fallback.tap()
            pause(1.5)
        } else {
            note("не найден таб «\(tab.label)»")
        }
    }

    // MARK: - Поиск элементов

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func byPrefix(_ app: XCUIApplication, _ prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    @MainActor
    @discardableResult
    private func waitForAny(_ app: XCUIApplication, ids: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if ids.contains(where: { element(app, $0).exists }) { return true }
            pause(0.5)
        } while Date() < deadline
        note("за \(Int(timeout)) с не появилось ни одного из: \(ids.joined(separator: ", "))")
        return false
    }

    @MainActor
    @discardableResult
    private func waitForPrefix(_ app: XCUIApplication, _ prefix: String, timeout: TimeInterval) -> Bool {
        if byPrefix(app, prefix).firstMatch.waitForExistence(timeout: timeout) { return true }
        note("за \(Int(timeout)) с не появилось элементов «\(prefix)*»")
        return false
    }

    /// Найти (с прокруткой) и нажать элемент по accessibilityIdentifier.
    @MainActor
    @discardableResult
    private func tapId(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 8, scroll: Bool = true) -> Bool {
        let target = element(app, id)
        let found = target.waitForExistence(timeout: timeout) || (scroll && reveal(target, in: app))
        guard found else {
            note("не найден элемент «\(id)»")
            return false
        }
        // Элементы контента докручиваем из-под навбара/таб-бара/липкого бара; закреплённые (scroll: false) — нет.
        if scroll, !isComfortablyVisible(target, in: app) { reveal(target, in: app) }
        if target.isHittable {
            target.tap()
        } else {
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        pause(1)
        return true
    }

    /// Прокрутить, пока элемент не окажется в видимой зоне (не под навбаром/таб-баром/липким баром).
    @MainActor
    @discardableResult
    private func reveal(_ target: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8, up: Bool = true) -> Bool {
        for _ in 0..<maxSwipes {
            if isComfortablyVisible(target, in: app) { return true }
            drag(app, times: 1, up: up)
        }
        if isComfortablyVisible(target, in: app) { return true }
        // Не нашли в одну сторону — пробуем в другую.
        for _ in 0..<maxSwipes {
            drag(app, times: 1, up: !up)
            if isComfortablyVisible(target, in: app) { return true }
        }
        return false
    }

    @MainActor
    private func isComfortablyVisible(_ target: XCUIElement, in app: XCUIApplication) -> Bool {
        guard target.exists, target.isHittable else { return false }
        let screen = app.frame
        let frame = target.frame
        return frame.minY > screen.minY + 90 && frame.maxY < screen.maxY - 150
    }

    /// Медленная прокрутка без инерции: ~35% высоты экрана за раз.
    @MainActor
    private func drag(_ app: XCUIApplication, times: Int = 1, up: Bool = true) {
        for _ in 0..<times {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.3))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.65))
            from.press(forDuration: 0.05, thenDragTo: to)
            pause(0.4)
        }
    }

    @MainActor
    private func dismissSheet(_ app: XCUIApplication) {
        let done = app.buttons["Готово"].firstMatch
        if done.waitForExistence(timeout: 2) {
            done.tap()
        } else {
            let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            top.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
        pause(1)
    }

    // MARK: - Снимки

    @MainActor
    private func snap(_ name: String, settle: TimeInterval = 2) {
        pause(settle)
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"], !dir.isEmpty else { return }
        let folder = URL(fileURLWithPath: dir, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            note("не удалось сохранить \(name).png: \(error.localizedDescription)")
        }
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func note(_ message: String) {
        print("[screenshots] \(name): \(message)")
    }
}
