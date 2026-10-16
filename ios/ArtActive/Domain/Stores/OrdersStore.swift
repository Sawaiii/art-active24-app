import Foundation
import Observation

/// «Мои заказы»: список, непрочитанные изменения статуса, создание заказов/заявок.
@MainActor
@Observable
final class OrdersStore {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var orders: [Order] = []
    private(set) var status: Status = .idle
    private(set) var hasMore = false
    /// id заказа → момент последнего изменения, который пользователь уже видел.
    private(set) var seen: [Int: Date]

    @ObservationIgnored private let repository: OrderRepository
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private var page = 1
    @ObservationIgnored private var loadingMore = false

    init(repository: OrderRepository, store: LocalStore) {
        self.repository = repository
        self.store = store
        let raw = store.load([String: Date].self, key: .seenOrders) ?? [:]
        seen = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    /// Число заказов с изменениями, которые пользователь ещё не открыл.
    var unseenCount: Int {
        orders.filter { isUnseen($0) }.count
    }

    func isUnseen(_ order: Order) -> Bool {
        guard let seenAt = seen[order.id] else { return order.history.count > 1 }
        return order.lastChange > seenAt
    }

    func load() async {
        if orders.isEmpty { status = .loading }
        do {
            let first = try await repository.orders(page: 1)
            orders = first.items
            hasMore = first.hasMore
            page = 1
            status = .loaded
        } catch {
            guard !error.isCancellation else { return }
            status = .failed(error.userMessage)
        }
    }

    func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let next = try await repository.orders(page: page + 1)
            let known = Set(orders.map(\.id))
            orders += next.items.filter { !known.contains($0.id) }
            hasMore = next.hasMore
            page += 1
        } catch {
            hasMore = false
        }
    }

    func order(id: Int) async throws -> Order {
        let order = try await repository.order(id: id)
        upsert(order)
        return order
    }

    func checkout(_ request: CheckoutRequest, idempotencyKey: String) async throws -> Order {
        let order = try await repository.checkout(request, idempotencyKey: idempotencyKey)
        upsert(order)
        markSeen(order)
        return order
    }

    func createRequest(_ request: RequestCreate, idempotencyKey: String) async throws -> Order {
        let order = try await repository.createRequest(request, idempotencyKey: idempotencyKey)
        upsert(order)
        markSeen(order)
        return order
    }

    func cancel(id: Int) async throws -> Order {
        let order = try await repository.cancel(id: id)
        upsert(order)
        markSeen(order)
        return order
    }

    func markSeen(_ order: Order) {
        seen[order.id] = order.lastChange
        let raw = Dictionary(uniqueKeysWithValues: seen.map { (String($0.key), $0.value) })
        store.save(raw, key: .seenOrders)
    }

    func reset() {
        orders = []
        status = .idle
        hasMore = false
    }

    private func upsert(_ order: Order) {
        if let index = orders.firstIndex(where: { $0.id == order.id }) {
            orders[index] = order
        } else {
            orders.insert(order, at: 0)
        }
    }
}
