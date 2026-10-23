import Foundation
import Observation

/// Скидка постоянного клиента (GET /v1/me/loyalty): процент, прогресс до следующего уровня.
/// Сама скидка считается сервером в quote и заказе — здесь только показ в профиле.
@MainActor
@Observable
final class LoyaltyStore {
    enum Status: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var loyalty: Loyalty?
    private(set) var status: Status = .idle

    @ObservationIgnored private let repository: ProfileRepository

    init(repository: ProfileRepository) {
        self.repository = repository
    }

    func load() async {
        if loyalty == nil { status = .loading }
        do {
            loyalty = try await repository.loyalty()
            status = .loaded
        } catch {
            guard !error.isCancellation else { return }
            status = .failed(error.userMessage)
        }
    }

    func reset() {
        loyalty = nil
        status = .idle
    }
}
