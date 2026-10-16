import Foundation
import Observation

/// Состояние входа. Токены живут в Keychain (`SessionManager`), здесь — пользователь для UI
/// и хуки, которые нужно выполнить после входа (слияние корзины, избранного, push).
@MainActor
@Observable
final class AuthStore {
    private(set) var user: User?
    var isLoggedIn: Bool { user != nil }

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let authRepository: AuthRepository
    @ObservationIgnored private let profileRepository: ProfileRepository
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private var signInHooks: [@MainActor () async -> Void] = []
    @ObservationIgnored private var beforeSignOutHooks: [@MainActor () async -> Void] = []
    @ObservationIgnored private var signOutHooks: [@MainActor (_ explicit: Bool) async -> Void] = []

    init(sessionManager: SessionManager, authRepository: AuthRepository, profileRepository: ProfileRepository, store: LocalStore) {
        self.sessionManager = sessionManager
        self.authRepository = authRepository
        self.profileRepository = profileRepository
        self.store = store
        user = store.load(User.self, key: .user)
    }

    func onSignIn(_ hook: @escaping @MainActor () async -> Void) { signInHooks.append(hook) }
    /// Пока токен ещё действует (например, DELETE /v1/me/devices).
    func beforeSignOut(_ hook: @escaping @MainActor () async -> Void) { beforeSignOutHooks.append(hook) }
    /// `explicit` — пользователь сам вышел (чистим локальные данные); false — сессия истекла.
    func onSignOut(_ hook: @escaping @MainActor (_ explicit: Bool) async -> Void) { signOutHooks.append(hook) }

    /// При старте: если токенов нет, а пользователь закэширован — сбрасываем.
    func restore() async {
        let hasSession = await sessionManager.hasSession
        guard hasSession else {
            if user != nil { setUser(nil) }
            return
        }
        await refreshUser()
    }

    func refreshUser() async {
        do {
            setUser(try await profileRepository.me())
        } catch let error as APIError where error == .unauthorized {
            await handleSessionLost()
        } catch {
            // Без сети остаёмся с закэшированным пользователем.
        }
    }

    func requestCode(phone: String) async throws -> CodeResponse {
        try await authRepository.requestCode(phone: phone)
    }

    func verify(phone: String, code: String) async throws -> AuthSession {
        let session = try await authRepository.verify(phone: phone, code: code)
        await sessionManager.store(session)
        setUser(session.user)
        for hook in signInHooks { await hook() }
        return session
    }

    func updateProfile(_ patch: ProfilePatch) async throws {
        setUser(try await profileRepository.update(patch))
    }

    func signOut() async {
        for hook in beforeSignOutHooks { await hook() }
        try? await authRepository.logout()
        await sessionManager.clear()
        setUser(nil)
        for hook in signOutHooks { await hook(true) }
    }

    /// Сервер отклонил refresh — сессия потеряна.
    func handleSessionLost() async {
        guard user != nil else { return }
        await sessionManager.clear()
        setUser(nil)
        for hook in signOutHooks { await hook(false) }
    }

    private func setUser(_ newValue: User?) {
        user = newValue
        if let newValue { store.save(newValue, key: .user) } else { store.remove(.user) }
    }
}
