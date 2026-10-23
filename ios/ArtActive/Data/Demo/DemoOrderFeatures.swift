import Foundation

// Личный кабинет демо-заказа (порт api/src/Orders/*): скидка постоянного клиента, машина на карте,
// состав из «КП», документы, отзыв и претензия. Чистые функции — состояние держит DemoBackend.

// MARK: - Скидка постоянного клиента

enum DemoLoyalty {
    struct Tier: Sendable {
        let threshold: Int
        let percent: Int
    }

    /// Уровни по сумме завершённых заказов — как LOYALTY_TIERS по умолчанию на сервере.
    static let tiers: [Tier] = [
        Tier(threshold: 0, percent: 0),
        Tier(threshold: 50_000, percent: 2),
        Tier(threshold: 150_000, percent: 3),
        Tier(threshold: 300_000, percent: 5),
        Tier(threshold: 500_000, percent: 7),
        Tier(threshold: 1_000_000, percent: 10),
        Tier(threshold: 2_000_000, percent: 15),
        Tier(threshold: 5_000_000, percent: 20),
        Tier(threshold: 10_000_000, percent: 25),
    ]

    /// Только демо: «история заказов на сайте» до приложения — чтобы скидка 2 % была видна сразу
    /// (в рабочем API сумма считается только по реальным завершённым заказам).
    static let baselineSpent = 120_000
    static let baselineOrders = 2

    /// floor(subtotal × percent / 100 + 0.5) — половина рубля вверх, как на сервере.
    static func amount(subtotal: Int, percent: Int) -> Int {
        (subtotal * percent + 50) / 100
    }

    static func title(_ percent: Int) -> String {
        "Скидка постоянного клиента \u{2212}\(percent)%"
    }

    static func discount(subtotal: Int, percent: Int) -> PriceDiscount? {
        guard percent > 0, subtotal > 0 else { return nil }
        return PriceDiscount(kind: .loyalty, title: title(percent), percent: percent, amount: amount(subtotal: subtotal, percent: percent))
    }

    static func tierIndex(spent: Int) -> Int {
        tiers.lastIndex { $0.threshold <= spent } ?? 0
    }

    static func summary(spent: Int, completedOrders: Int) -> Loyalty {
        let index = tierIndex(spent: spent)
        let ladder = tiers.enumerated().map { LoyaltyTier(level: $0.offset + 1, threshold: $0.element.threshold, percent: $0.element.percent) }
        let next: LoyaltyNextTier? = index + 1 < tiers.count
            ? LoyaltyNextTier(
                level: index + 2,
                percent: tiers[index + 1].percent,
                threshold: tiers[index + 1].threshold,
                remaining: max(0, tiers[index + 1].threshold - spent)
            )
            : nil
        return Loyalty(
            percent: tiers[index].percent,
            source: .tier,
            tier: ladder[index],
            spent: spent,
            completedOrders: completedOrders,
            nextTier: next,
            tiers: ladder,
            personal: nil
        )
    }

    /// Скидка к quote: строки не меняются, total = subtotal − скидка.
    static func apply(_ quote: Quote, percent: Int) -> Quote {
        guard let discount = Self.discount(subtotal: quote.total, percent: percent) else { return quote }
        return Quote(
            lines: quote.lines,
            total: quote.total - discount.amount,
            hasOnRequest: quote.hasOnRequest,
            count: quote.count,
            subtotal: quote.total,
            discount: discount
        )
    }
}

// MARK: - Машина на карте

struct DemoCoordinate: Sendable {
    let lat: Double
    let lng: Double
}

enum DemoVehicle {
    /// Сколько едет машина в демо (статус «В пути» длится 120 с).
    static let duration: TimeInterval = 105
    static let fallbackWarehouse = DemoCoordinate(lat: 55.7963, lng: 37.5378)
    static let destinations: [DemoCoordinate] = [
        DemoCoordinate(lat: 55.7158, lng: 37.5537), // Лужники
        DemoCoordinate(lat: 55.8263, lng: 37.6377), // ВДНХ
        DemoCoordinate(lat: 55.7920, lng: 37.6770), // Сокольники
        DemoCoordinate(lat: 55.8237, lng: 37.3876), // Крокус
        DemoCoordinate(lat: 55.6670, lng: 37.6705), // Коломенское
    ]
    private static let waypoints = 7

    static func location(orderId: Int, startedAt: Date, now: Date, warehouse: DemoCoordinate) -> VehicleLocation {
        let destination = destinations[abs(orderId) % destinations.count]
        let path = route(from: warehouse, to: destination)
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let progress = min(1, elapsed / duration)
        let arrived = progress >= 1
        let (point, heading) = position(on: path, fraction: ease(progress))
        let tick = Int(now.timeIntervalSince1970 / 5)
        let seed = (tick &* 7919 &+ orderId &* 104_729) % 29
        let accuracy = Double(12 + (seed + 29) % 29)
        return VehicleLocation(
            status: arrived ? .arrived : .enRoute,
            lat: point.lat,
            lng: point.lng,
            accuracy: accuracy,
            heading: heading,
            updatedAt: Date(timeIntervalSince1970: Double(tick) * 5),
            eta: arrived ? nil : startedAt.addingTimeInterval(duration),
            source: .driver,
            vehicle: "Газель · А123ВС 777",
            driverName: "Сергей"
        )
    }

    /// Плавная дуга от склада до площадки (как объезд по городу).
    static func route(from start: DemoCoordinate, to end: DemoCoordinate) -> [DemoCoordinate] {
        let dLat = end.lat - start.lat
        let dLng = end.lng - start.lng
        return (0...waypoints).map { index -> DemoCoordinate in
            let t = Double(index) / Double(waypoints)
            let bend = sin(Double.pi * t) * 0.18
            return DemoCoordinate(lat: start.lat + dLat * t - dLng * bend * 0.5, lng: start.lng + dLng * t + dLat * bend)
        }
    }

    private static func ease(_ p: Double) -> Double {
        p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
    }

    /// Точка на ломаной по доле длины и курс текущего отрезка.
    private static func position(on path: [DemoCoordinate], fraction: Double) -> (DemoCoordinate, Double) {
        guard path.count > 1 else { return (path.first ?? fallbackWarehouse, 0) }
        let lengths = zip(path, path.dropFirst()).map { distance($0, $1) }
        let total = lengths.reduce(0, +)
        var remaining = total * min(max(fraction, 0), 1)
        for (index, length) in lengths.enumerated() {
            let a = path[index]
            let b = path[index + 1]
            if remaining <= length || index == lengths.count - 1 {
                let t = length > 0 ? min(remaining / length, 1) : 1
                let point = DemoCoordinate(lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t)
                return (point, bearing(a, b))
            }
            remaining -= length
        }
        return (path[path.count - 1], 0)
    }

    private static func distance(_ a: DemoCoordinate, _ b: DemoCoordinate) -> Double {
        let scale = cos((a.lat + b.lat) / 2 * Double.pi / 180)
        return hypot(b.lat - a.lat, (b.lng - a.lng) * scale)
    }

    /// Начальный азимут a → b, градусы 0…360.
    static func bearing(_ a: DemoCoordinate, _ b: DemoCoordinate) -> Double {
        let lat1 = a.lat * Double.pi / 180
        let lat2 = b.lat * Double.pi / 180
        let deltaLng = (b.lng - a.lng) * Double.pi / 180
        let y = sin(deltaLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLng)
        let degrees = atan2(y, x) * 180 / Double.pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

// MARK: - Состав заказа

enum DemoComposition {
    static let fallbackSection = "Позиции заказа"
    static let deliveryNote = "Стоимость доставки рассчитает менеджер"
    static let vatNote = "Без НДС (УСН)"

    /// Позиции корзины по разделам (корневой раздел каталога); после подтверждения «менеджер
    /// прикладывает КП» — версия 2 с разделом «Логистика».
    static func build(order: DemoOrder, history: [StatusEvent], dataset: DemoDataset) -> OrderComposition {
        guard !order.lines.isEmpty else {
            return OrderComposition(
                source: .empty, kpNumber: nil, kpDate: nil, version: 1, updatedAt: order.createdAt, title: nil,
                sections: [], subtotal: 0, discounts: nil, delivery: nil, deliveryNote: nil, total: 0, vatNote: nil,
                hasOnRequest: nil
            )
        }
        var sections = cartSections(order.lines, dataset: dataset)
        let percent = order.discountPercent ?? 0
        let isDelivery = order.delivery?.method == .delivery
        let confirmedAt = history.first { $0.status == .confirmed }?.at

        guard let confirmedAt else {
            let subtotal = sections.reduce(0) { $0 + $1.subtotal }
            return OrderComposition(
                source: .cart, kpNumber: nil, kpDate: nil, version: 1, updatedAt: order.createdAt, title: nil,
                sections: sections, subtotal: subtotal,
                discounts: DemoLoyalty.discount(subtotal: subtotal, percent: percent).map { [$0] },
                delivery: nil, deliveryNote: isDelivery ? deliveryNote : nil, total: order.total, vatNote: vatNote,
                hasOnRequest: order.hasOnRequest
            )
        }

        if isDelivery {
            let logistics = [
                CompositionLine(name: "Доставка Газель 15 м²", art: nil, qty: 1, unit: "рейс", days: nil, price: 3500, sum: 3500, note: nil, onRequest: nil),
                CompositionLine(name: "Монтаж и демонтаж", art: nil, qty: 1, unit: "усл", days: nil, price: 2000, sum: 2000, note: nil, onRequest: nil),
            ]
            sections.append(CompositionSection(id: "logistics", title: "Логистика", lines: logistics, subtotal: 5500))
        }
        let subtotal = sections.reduce(0) { $0 + $1.subtotal }
        let discount = DemoLoyalty.discount(subtotal: subtotal, percent: percent)
        return OrderComposition(
            source: .kp, kpNumber: kpNumber(order.id), kpDate: DayDate.string(from: confirmedAt), version: 2,
            updatedAt: confirmedAt, title: nil, sections: sections, subtotal: subtotal,
            discounts: discount.map { [$0] }, delivery: nil, deliveryNote: nil,
            total: subtotal - (discount?.amount ?? 0), vatNote: vatNote, hasOnRequest: order.hasOnRequest
        )
    }

    static func kpNumber(_ orderId: Int) -> String {
        "КП-2026-" + String(format: "%04d", orderId)
    }

    private static func cartSections(_ lines: [OrderLine], dataset: DemoDataset) -> [CompositionSection] {
        var titles: [String] = []
        var grouped: [String: [CompositionLine]] = [:]
        for line in lines {
            let root = line.productId.flatMap { dataset.product($0)?.breadcrumbs?.first?.name } ?? fallbackSection
            if grouped[root] == nil { titles.append(root) }
            grouped[root, default: []].append(compositionLine(line))
        }
        return titles.enumerated().map { index, title -> CompositionSection in
            let items = grouped[title] ?? []
            return CompositionSection(id: "section-\(index + 1)", title: title, lines: items, subtotal: items.reduce(0) { $0 + $1.sum })
        }
    }

    private static func compositionLine(_ line: OrderLine) -> CompositionLine {
        var name = line.productName ?? "Позиция"
        if let complect = line.complectTitle, !complect.isEmpty { name += " — " + complect }
        let time = line.input?.time
        var notes: [String] = []
        if time?.unit == .hours, let label = line.timeLabel, !label.isEmpty { notes.append(label) }
        for extra in line.extras ?? [] {
            guard let extraName = extra.name else { continue }
            let qty = extra.qty ?? 1
            notes.append(qty > 1 ? "+ \(extraName) × \(qty)" : "+ \(extraName)")
        }
        return CompositionLine(
            name: name,
            art: line.art,
            qty: Double(line.qty ?? 1),
            unit: line.qtyUnit ?? "шт",
            days: time?.unit == .days ? time?.value : nil,
            price: line.unitPrice ?? 0,
            sum: line.total ?? 0,
            note: notes.isEmpty ? nil : notes.joined(separator: ", "),
            onRequest: line.onRequest == true ? true : nil
        )
    }
}

// MARK: - Документы

enum DemoDocuments {
    /// Документы появляются по ходу заказа (до отмены — что успело появиться). Новые сверху.
    static func list(order: DemoOrder, history: [StatusEvent]) -> [OrderDocument] {
        func reached(_ status: OrderStatus) -> Date? { history.first { $0.status == status }?.at }
        let number = String(format: "%04d", order.id)
        var docs: [OrderDocument] = []
        if let at = reached(.confirmed) {
            docs.append(make(order, "crm-kp", "Коммерческое предложение \(DemoComposition.kpNumber(order.id))", .kp, .crm, at))
            docs.append(make(order, "m-contract", "Договор аренды № \(number)", .contract, .manager, at))
        }
        if let at = reached(.inProgress) {
            docs.append(make(order, "vc-act-accept", "Акт приёма", .act, .vyzovchat, at))
        }
        if let at = reached(.completed) {
            docs.append(make(order, "vc-act-return", "Акт возврата", .act, .vyzovchat, at))
            docs.append(make(order, "crm-invoice", "Счёт № \(number)", .invoice, .crm, at))
        }
        return Array(docs.reversed())
    }

    // swiftlint:disable:next function_parameter_count
    private static func make(
        _ order: DemoOrder, _ id: String, _ title: String, _ kind: DocumentKind, _ source: DocumentSource, _ at: Date
    ) -> OrderDocument {
        let url = DemoBackend.baseURL.appendingPathComponent("demo-docs/\(order.id)-\(id).pdf").absoluteString
        return OrderDocument(
            id: id, title: title, kind: kind, source: source, date: DayDate.string(from: at),
            url: url, size: nil, mime: "application/pdf"
        )
    }
}

// MARK: - Отзыв и претензия

enum DemoFeedback {
    static let reviewEditWindow: TimeInterval = 7 * 86_400
    static let claimWindowAfterCompletion: TimeInterval = 14 * 86_400
    /// Симуляция менеджера: претензию принимают через 20 с.
    static let claimAcceptDelay: TimeInterval = 20
    static let maxOpenClaims = 3
    static let chatURL = "https://vyzovchat.ru"
    static let acceptedComment = "Менеджер принял претензию и открыл чат «Жалобы» в Вызов Чате"

    struct ClaimDraft {
        let category: ClaimCategory
        let description: String
        let contactPreference: ContactPreference
        let photos: [ClaimPhoto]
    }

    static func completedAt(_ order: DemoOrder) -> Date {
        let offset = DemoOrderTimeline.steps.first { $0.status == .completed }?.offset ?? 480
        return order.createdAt.addingTimeInterval(offset)
    }

    static func canReview(status: OrderStatus, review: DemoReview?, now: Date) -> Bool {
        guard status == .completed else { return false }
        guard let review else { return true }
        return now < review.createdAt.addingTimeInterval(reviewEditWindow)
    }

    static func canClaim(order: DemoOrder, status: OrderStatus, now: Date) -> Bool {
        switch status {
        case .inProgress: return true
        case .completed: return now <= completedAt(order).addingTimeInterval(claimWindowAfterCompletion)
        default: return false
        }
    }

    static func present(_ review: DemoReview, now: Date) -> OrderReview {
        let until = review.createdAt.addingTimeInterval(reviewEditWindow)
        return OrderReview(
            rating: review.rating, text: review.text, createdAt: review.createdAt, updatedAt: review.updatedAt,
            editableUntil: until, canEdit: now < until
        )
    }

    static func status(of claim: DemoClaim, now: Date) -> ClaimStatus {
        now >= claim.createdAt.addingTimeInterval(claimAcceptDelay) ? .accepted : .submitted
    }

    static func present(_ claim: DemoClaim, orderNumber: String, now: Date) -> OrderClaim {
        let current = Self.status(of: claim, now: now)
        let accepted = current == .accepted
        return OrderClaim(
            id: claim.id,
            orderId: claim.orderId,
            orderNumber: orderNumber,
            category: claim.category,
            categoryLabel: categoryLabel(claim.category),
            description: claim.description,
            contactPreference: claim.contactPreference,
            photos: claim.photos.isEmpty ? nil : claim.photos,
            status: current,
            statusLabel: statusLabel(current),
            managerComment: accepted ? acceptedComment : nil,
            chatUrl: accepted ? chatURL : nil,
            chatAppUrl: nil,
            createdAt: claim.createdAt,
            updatedAt: accepted ? claim.createdAt.addingTimeInterval(claimAcceptDelay) : nil
        )
    }

    static func categoryLabel(_ category: ClaimCategory) -> String {
        switch category {
        case .late: return "Опоздание"
        case .quality: return "Качество"
        case .incomplete: return "Комплектность"
        case .staff: return "Персонал"
        case .other, .unknown: return "Другое"
        }
    }

    static func statusLabel(_ status: ClaimStatus) -> String {
        switch status {
        case .submitted: return "Отправлена"
        case .accepted: return "Принята"
        case .resolved: return "Решена"
        case .rejected: return "Отклонена"
        case .unknown: return "Статус уточняется"
        }
    }

    // MARK: Разбор тела запроса

    static func parseReview(_ body: [String: Any]) throws -> (rating: Int, text: String?) {
        var errors: [String: String] = [:]
        let rating = body.demoInt("rating") ?? 0
        if !(1...5).contains(rating) { errors["rating"] = "Оценка от 1 до 5" }
        var text: String?
        if body.demoHas("text") {
            if let raw = body["text"] as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 2000 { errors["text"] = "Не больше 2000 символов" }
                text = trimmed.isEmpty ? nil : trimmed
            } else {
                errors["text"] = "Ожидается текст"
            }
        }
        if !errors.isEmpty { throw DemoError.validation(errors) }
        return (rating, text)
    }

    static func parseClaim(_ body: [String: Any]) throws -> ClaimDraft {
        var errors: [String: String] = [:]
        let category = body.demoString("category").flatMap(ClaimCategory.init(rawValue:)) ?? .unknown
        if category == .unknown { errors["category"] = "Выберите, что случилось" }

        let description = (body.demoString("description") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if description.count < 10 {
            errors["description"] = "Опишите, что случилось, — хотя бы 10 символов"
        } else if description.count > 2000 {
            errors["description"] = "Не больше 2000 символов"
        }

        var contact = ContactPreference.call
        if body.demoHas("contactPreference") {
            let parsed = body.demoString("contactPreference").flatMap(ContactPreference.init(rawValue:)) ?? .unknown
            if parsed == .unknown { errors["contactPreference"] = "Неизвестный способ связи" } else { contact = parsed }
        }

        var photos: [ClaimPhoto] = []
        if body.demoHas("photos") {
            let raw = body["photos"] as? [Any] ?? []
            let urls = raw.compactMap { ($0 as? [String: Any])?.demoString("url") }
            let valid = (body["photos"] is [Any]) && raw.count <= 10 && urls.count == raw.count && urls.allSatisfy { url in
                url.count <= 1000 && url.lowercased().hasPrefix("https://") && URL(string: url)?.host != nil
            }
            if valid { photos = urls.map { ClaimPhoto(url: $0) } } else { errors["photos"] = "Фото — до 10 ссылок https" }
        }

        if !errors.isEmpty { throw DemoError.validation(errors) }
        return ClaimDraft(category: category, description: description, contactPreference: contact, photos: photos)
    }
}
