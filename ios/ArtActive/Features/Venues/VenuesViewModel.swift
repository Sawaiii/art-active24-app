import Foundation
import Observation

/// Пилюля применённого фильтра площадок.
struct AppliedChip: Hashable, Identifiable {
    let id: String
    let title: String
}

@MainActor
@Observable
final class VenuesViewModel {
    private(set) var state: ViewState<Void> = .loading
    private(set) var venues: [VenueSummary] = []
    private(set) var total: Int?
    private(set) var counts: [String: [String: Int]] = [:]
    private(set) var filters: VenueFiltersPayload?
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?
    private(set) var query: VenueQuery

    let title: String?

    @ObservationIgnored private let repository: VenueRepository
    @ObservationIgnored private var page = 1
    @ObservationIgnored private var hasMore = false

    init(collectionId: Int?, title: String?, repository: VenueRepository) {
        self.title = title
        self.repository = repository
        query = VenueQuery(collection: collectionId)
    }

    func load() async {
        async let listLoad: Void = reload()
        async let filtersLoad: Void = loadFilters()
        _ = await (listLoad, filtersLoad)
    }

    private func loadFilters() async {
        guard filters == nil else { return }
        filters = try? await repository.filters()
    }

    func reload() async {
        if venues.isEmpty { state = .loading }
        loadMoreError = nil
        do {
            let result = try await repository.venues(query: query, page: 1)
            venues = result.page.items
            total = result.page.total
            counts = result.counts
            hasMore = result.page.hasMore
            page = 1
            state = venues.isEmpty ? .empty : .content(())
        } catch {
            guard !error.isCancellation else { return }
            if venues.isEmpty { state = .error(error.userMessage) }
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let result = try await repository.venues(query: query, page: page + 1)
            let known = Set(venues.map(\.id))
            venues += result.page.items.filter { !known.contains($0.id) }
            hasMore = result.page.hasMore
            page += 1
        } catch {
            guard !error.isCancellation else { return }
            loadMoreError = error.userMessage
        }
    }

    func apply(_ newQuery: VenueQuery) async {
        guard newQuery != query else { return }
        query = newQuery
        venues = []
        await reload()
    }

    /// Пилюли применённых фильтров (имя опции) — для быстрого снятия.
    var appliedChips: [AppliedChip] {
        guard let filters else { return [] }
        var chips: [AppliedChip] = []
        func add(_ ids: Set<Int>, _ options: [FilterOption]?, prefix: String) {
            for option in options ?? [] {
                if let id = option.id, ids.contains(id), let name = option.name { chips.append(AppliedChip(id: prefix + String(id), title: name)) }
            }
        }
        add(query.events, filters.events, prefix: "e")
        add(query.types, filters.types, prefix: "t")
        add(query.metro, filters.metro, prefix: "m")
        add(query.props, filters.props, prefix: "p")
        return chips
    }

    func removeChip(_ chipId: String) async {
        guard let kind = chipId.first, let id = Int(chipId.dropFirst()) else { return }
        var next = query
        switch kind {
        case "e": next.events.remove(id)
        case "t": next.types.remove(id)
        case "m": next.metro.remove(id)
        case "p": next.props.remove(id)
        default: return
        }
        await apply(next)
    }
}

@MainActor
@Observable
final class VenueDetailViewModel {
    let venueId: Int
    private(set) var state: ViewState<Venue> = .loading
    @ObservationIgnored private let repository: VenueRepository

    init(venueId: Int, repository: VenueRepository) {
        self.venueId = venueId
        self.repository = repository
    }

    func load() async {
        if state.content == nil { state = .loading }
        do {
            state = .content(try await repository.venue(id: venueId))
        } catch {
            guard !error.isCancellation else { return }
            if state.content == nil { state = .error(error.userMessage) }
        }
    }
}
