import Foundation
import Observation

/// Избранное: локально для гостя, синхронизация с `/v1/me/favorites` после входа.
@MainActor
@Observable
final class FavoritesStore {
    private(set) var items: [ProductSummary]

    @ObservationIgnored private let repository: ProfileRepository
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let isLoggedIn: @MainActor () -> Bool
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(repository: ProfileRepository, store: LocalStore, isLoggedIn: @escaping @MainActor () -> Bool) {
        self.repository = repository
        self.store = store
        self.isLoggedIn = isLoggedIn
        items = store.load([ProductSummary].self, key: .favorites) ?? []
    }

    func contains(_ id: Int) -> Bool { items.contains { $0.id == id } }

    /// Переключить; возвращает новое состояние (true — добавлено).
    @discardableResult
    func toggle(_ product: ProductSummary) -> Bool {
        let added: Bool
        if let index = items.firstIndex(where: { $0.id == product.id }) {
            items.remove(at: index)
            added = false
        } else {
            items.insert(product, at: 0)
            added = true
        }
        persist()
        scheduleSync()
        return added
    }

    func remove(_ id: Int) {
        items.removeAll { $0.id == id }
        persist()
        scheduleSync()
    }

    /// Слияние после входа: серверные + локальные.
    func mergeAfterSignIn() async {
        do {
            let server = try await repository.favorites()
            var merged = items
            for product in server where !merged.contains(where: { $0.id == product.id }) {
                merged.append(product)
            }
            let result = try await repository.setFavorites(merged.map(\.id))
            items = result.isEmpty ? merged : result
            persist()
        } catch {
            // Локальный список остаётся; синхронизируемся при следующем изменении.
        }
    }

    func refreshFromServer() async {
        guard isLoggedIn() else { return }
        if let server = try? await repository.favorites() {
            items = server
            persist()
        }
    }

    /// Явный выход: локальное избранное очищается.
    func clearLocal() {
        syncTask?.cancel()
        items = []
        store.remove(.favorites)
    }

    private func persist() { store.save(items, key: .favorites) }

    private func scheduleSync() {
        guard isLoggedIn() else { return }
        syncTask?.cancel()
        let ids = items.map(\.id)
        syncTask = Task { [repository] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            _ = try? await repository.setFavorites(ids)
        }
    }
}

/// «Вы смотрели» — последние открытые карточки (локально).
@MainActor
@Observable
final class RecentlyViewedStore {
    private(set) var items: [ProductSummary]
    @ObservationIgnored private let store: LocalStore
    private static let limit = 20

    init(store: LocalStore) {
        self.store = store
        items = store.load([ProductSummary].self, key: .recentlyViewed) ?? []
    }

    func record(_ product: ProductSummary) {
        var updated = items.filter { $0.id != product.id }
        updated.insert(product, at: 0)
        items = Array(updated.prefix(Self.limit))
        store.save(items, key: .recentlyViewed)
    }

    func clear() {
        items = []
        store.remove(.recentlyViewed)
    }
}

/// История поисковых запросов.
@MainActor
@Observable
final class SearchHistoryStore {
    private(set) var queries: [String]
    @ObservationIgnored private let store: LocalStore
    private static let limit = 10

    static var popular: [String] {
        [
            String(localized: "Батут"), String(localized: "Стол"), String(localized: "Фотозона"),
            String(localized: "Шатёр"), String(localized: "Кейтеринг"), String(localized: "Мастер-класс"),
            String(localized: "Площадка"),
        ]
    }

    init(store: LocalStore) {
        self.store = store
        queries = store.load([String].self, key: .searchHistory) ?? []
    }

    func add(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        var updated = queries.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        queries = Array(updated.prefix(Self.limit))
        store.save(queries, key: .searchHistory)
    }

    func remove(_ query: String) {
        queries.removeAll { $0 == query }
        store.save(queries, key: .searchHistory)
    }

    func clear() {
        queries = []
        store.remove(.searchHistory)
    }
}
