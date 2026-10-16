import Foundation
import Observation

/// Ключ позиции корзины — как состояние сайта `complekt_sub_priceType`.
/// Для строки-опции (без комплекта) ключ различает набор допов.
struct CartLineKey: Hashable, Sendable {
    let productId: Int
    let complectId: Int?
    let subId: String?
    let priceType: PriceType
    var options: [String] = []
}

extension CartItemInput {
    var isOptionLine: Bool { complectId == nil }

    var lineKey: CartLineKey {
        CartLineKey(
            productId: productId,
            complectId: complectId,
            subId: subId,
            priceType: priceType ?? .rent,
            options: complectId == nil ? (extras ?? []).map(\.id).sorted() : []
        )
    }

    /// Строка-опция: допы товара отдельной позицией (как кнопки add-cart опций на сайте).
    static func option(productId: Int, extraIds: [String], qty: Int = 1) -> CartItemInput {
        CartItemInput(productId: productId, complectId: nil, priceType: .rent, qty: qty, extras: extraIds.map { ExtraSelection(id: $0) })
    }
}

/// Корзина: состав хранится локально (гость тоже может всё до оформления),
/// цены — только из серверного quote. У авторизованного состав синхронизируется
/// с серверной корзиной (`PUT /v1/cart`).
@MainActor
@Observable
final class CartStore {
    enum QuoteStatus: Equatable {
        case idle
        case loading
        case failed(String)
    }

    private(set) var items: [CartItemInput]
    private(set) var quote: Quote?
    private(set) var quoteStatus: QuoteStatus = .idle
    /// Растёт при каждом добавлении — триггер «подпрыгивания» бейджа в таб-баре.
    private(set) var addPulse = 0

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    @ObservationIgnored private let repository: CartRepository
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let isLoggedIn: @MainActor () -> Bool
    @ObservationIgnored private var quoteTask: Task<Void, Never>?
    private static let debounce: Duration = .milliseconds(350)

    init(repository: CartRepository, store: LocalStore, isLoggedIn: @escaping @MainActor () -> Bool) {
        self.repository = repository
        self.store = store
        self.isLoggedIn = isLoggedIn
        items = store.load([CartItemInput].self, key: .cart) ?? []
    }

    // MARK: - Queries

    func item(for key: CartLineKey) -> CartItemInput? {
        items.first { $0.lineKey == key }
    }

    func contains(_ key: CartLineKey) -> Bool { item(for: key) != nil }

    /// Строка серверного расчёта для позиции.
    func quoteLine(for item: CartItemInput) -> QuoteLine? {
        quote?.lines.first { $0.input.lineKey == item.lineKey }
    }

    // MARK: - Mutations

    /// Добавить или заменить позицию с тем же ключом.
    func add(_ item: CartItemInput) {
        if let index = items.firstIndex(where: { $0.lineKey == item.lineKey }) {
            items[index] = item
        } else {
            items.append(item)
        }
        addPulse += 1
        changed()
    }

    /// Синхронизация конфигурации позиции, уже лежащей в корзине.
    func update(_ item: CartItemInput) {
        guard let index = items.firstIndex(where: { $0.lineKey == item.lineKey }), items[index] != item else { return }
        items[index] = item
        changed()
    }

    func setQty(_ qty: Int, for key: CartLineKey) {
        guard let index = items.firstIndex(where: { $0.lineKey == key }) else { return }
        var updated = items[index]
        updated.qty = min(max(qty, 1), Configurator.maxQty)
        guard updated != items[index] else { return }
        items[index] = updated
        changed()
    }

    /// Удалить позицию; возвращает её и место — для Undo.
    @discardableResult
    func remove(_ key: CartLineKey) -> (item: CartItemInput, index: Int)? {
        guard let index = items.firstIndex(where: { $0.lineKey == key }) else { return nil }
        let removed = items.remove(at: index)
        changed()
        return (removed, index)
    }

    func restore(_ item: CartItemInput, at index: Int) {
        guard !contains(item.lineKey) else { return }
        items.insert(item, at: min(max(index, 0), items.count))
        changed()
    }

    /// Повторить заказ: позиции заказа добавляются к текущей корзине.
    func addAll(_ newItems: [CartItemInput]) {
        guard !newItems.isEmpty else { return }
        for item in newItems {
            if let index = items.firstIndex(where: { $0.lineKey == item.lineKey }) {
                items[index] = item
            } else {
                items.append(item)
            }
        }
        addPulse += 1
        changed()
    }

    func clear() {
        items = []
        quote = Quote(lines: [], total: 0, hasOnRequest: false, count: 0)
        persist()
        if isLoggedIn() { scheduleQuote(immediately: true) }
    }

    // MARK: - Quote

    func refreshQuote() async {
        quoteTask?.cancel()
        await loadQuote()
    }

    /// После входа: серверная корзина + гостевая → одна, сервер — источник цен.
    func mergeAfterSignIn() async {
        do {
            let server = try await repository.serverCart()
            var merged = server.lines.map(\.input)
            for item in items where !merged.contains(where: { $0.lineKey == item.lineKey }) {
                merged.append(item)
            }
            items = merged
            persist()
            if merged.count != server.lines.count {
                quote = try await repository.replaceServerCart(merged)
            } else {
                quote = server
            }
            quoteStatus = .idle
        } catch {
            quoteStatus = .failed(error.userMessage)
        }
    }

    /// Выход: явный — локальная корзина очищается; истёкшая сессия — остаётся гостевой.
    func handleSignOut(explicit: Bool) {
        quoteTask?.cancel()
        if explicit {
            items = []
            quote = Quote(lines: [], total: 0, hasOnRequest: false, count: 0)
            quoteStatus = .idle
            persist()
        } else {
            scheduleQuote(immediately: true)
        }
    }

    private func changed() {
        persist()
        scheduleQuote(immediately: false)
    }

    private func persist() {
        store.save(items, key: .cart)
    }

    private func scheduleQuote(immediately: Bool) {
        quoteTask?.cancel()
        quoteTask = Task { [weak self] in
            if !immediately {
                try? await Task.sleep(for: CartStore.debounce)
            }
            guard !Task.isCancelled else { return }
            await self?.loadQuote()
        }
    }

    private func loadQuote() async {
        let snapshot = items
        if snapshot.isEmpty, !isLoggedIn() {
            quote = Quote(lines: [], total: 0, hasOnRequest: false, count: 0)
            quoteStatus = .idle
            return
        }
        quoteStatus = .loading
        do {
            let result: Quote
            if isLoggedIn() {
                result = try await repository.replaceServerCart(snapshot)
            } else {
                result = try await repository.quote(snapshot)
            }
            guard !Task.isCancelled, snapshot == items else { return }
            quote = result
            quoteStatus = .idle
        } catch {
            guard !error.isCancellation else { return }
            quoteStatus = .failed(error.userMessage)
        }
    }
}
