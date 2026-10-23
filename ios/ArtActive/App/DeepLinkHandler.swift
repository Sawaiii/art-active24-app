import Foundation
import OSLog

/// Universal links (art-active24.ru/…) и схема `artactive24://` → экран приложения.
/// Ссылки сайта разбирает сервер (`/v1/resolve`); неизвестное открывается в Safari.
@MainActor
final class DeepLinkHandler {
    private let catalog: CatalogRepository
    private let router: Router
    private let logger = Logger(subsystem: "ru.artactive24.app", category: "deeplink")

    init(catalog: CatalogRepository, router: Router) {
        self.catalog = catalog
        self.router = router
    }

    func handle(_ url: URL) {
        if url.scheme?.lowercased() == AppConfig.urlScheme {
            handleScheme(url)
            return
        }
        guard let host = url.host?.lowercased(), AppConfig.siteHosts.contains(host) else {
            logger.info("Чужой хост — игнорируем: \(url.absoluteString, privacy: .public)")
            return
        }
        Task { await resolve(url) }
    }

    /// `artactive24://product/123`, `artactive24://category/81`, `artactive24://venue/5`, `artactive24://order/42`.
    private func handleScheme(_ url: URL) {
        let parts = ([url.host ?? ""] + url.pathComponents.filter { $0 != "/" }).filter { !$0.isEmpty }
        guard parts.count >= 2, let id = Int(parts[1]), id > 0 else { return }
        switch parts[0] {
        case "product": router.push(.product(id: id, preselect: nil), in: .home)
        case "category": router.push(.category(id: id, title: nil), in: .catalog)
        case "venue": router.push(.venue(id: id), in: .catalog)
        case "order": router.openOrder(id: id)
        default: break
        }
    }

    private func resolve(_ url: URL) async {
        let path = url.path.isEmpty ? "/" : url.path
        guard path != "/" else {
            router.selectedTab = .home
            return
        }
        do {
            let target = try await catalog.resolve(path: path)
            route(target, original: url)
        } catch {
            logger.error("resolve \(path, privacy: .public): \(String(describing: error), privacy: .public)")
            router.openWeb(url)
        }
    }

    private func route(_ target: ResolvePayload, original: URL) {
        switch (target.type, target.id) {
        case let (.product?, id?):
            let preselect = ProductPreselection(
                complectId: target.complectId,
                subId: target.subId,
                priceType: target.priceType.flatMap(PriceType.init(rawValue:))
            )
            router.push(.product(id: id, preselect: preselect), in: .home)
        case let (.category?, id?):
            router.push(.category(id: id, title: nil), in: .catalog)
        case let (.venue?, id?):
            router.push(.venue(id: id), in: .catalog)
        case (.caseStudy?, _):
            guard let slug = target.slug, !slug.isEmpty else {
                router.openWeb(original)
                return
            }
            router.push(.caseStudy(slug: slug, title: nil), in: .home)
        case (.cases?, _):
            router.push(.cases(categoryId: nil), in: .home)
        case (.sale?, _):
            router.push(.sale, in: .home)
        default:
            router.openWeb(target.url?.resolvedURL ?? original)
        }
    }
}
