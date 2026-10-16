import Observation
import UIKit
import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case home, catalog, cart, favorites, profile
}

enum InfoPage: String, Hashable {
    case contacts, delivery, rentalTerms
}

/// Все экраны внутри стеков табов.
enum Route: Hashable {
    case catalogLevel(CategoryNode)
    case category(id: Int, title: String?)
    case product(id: Int, preselect: ProductPreselection?)
    case venues(collectionId: Int?, title: String?)
    case venue(id: Int)
    case search
    case orders
    case order(id: Int)
    case favorites
    case profileEdit
    case info(InfoPage)
    case checkout
}

struct WebPage: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Навигация: выбранный таб, стек каждого таба, глобальные модальные окна.
@MainActor
@Observable
final class Router {
    var selectedTab: AppTab = .home
    var paths: [AppTab: [Route]] = [:]
    var webPage: WebPage?
    var isLoginPresented = false

    @ObservationIgnored private var afterLogin: (@MainActor () -> Void)?

    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { self.paths[tab] ?? [] },
            set: { self.paths[tab] = $0 }
        )
    }

    /// Выбор таба; повторный тап по активному — назад к корню.
    var tabSelection: Binding<AppTab> {
        Binding(
            get: { self.selectedTab },
            set: { newValue in
                if newValue == self.selectedTab {
                    self.popToRoot(newValue)
                } else {
                    Haptics.play(.selection)
                    self.selectedTab = newValue
                }
            }
        )
    }

    func push(_ route: Route, in tab: AppTab? = nil) {
        let target = tab ?? selectedTab
        if let tab { selectedTab = tab }
        paths[target, default: []].append(route)
    }

    func popToRoot(_ tab: AppTab) {
        paths[tab] = []
    }

    func show(_ tab: AppTab, routes: [Route]) {
        selectedTab = tab
        paths[tab] = routes
    }

    func openWeb(_ url: URL) {
        if SafariView.canOpen(url) {
            webPage = WebPage(url: url)
        } else {
            UIApplication.shared.open(url)
        }
    }

    func openOrder(id: Int) {
        show(.profile, routes: [.orders, .order(id: id)])
    }

    /// Выполнить действие, требующее входа (оформление, заявка).
    func requireLogin(isLoggedIn: Bool, then action: @escaping @MainActor () -> Void) {
        if isLoggedIn {
            action()
        } else {
            afterLogin = action
            isLoginPresented = true
        }
    }

    func loginFinished(success: Bool) {
        isLoginPresented = false
        let action = afterLogin
        afterLogin = nil
        if success { action?() }
    }
}
