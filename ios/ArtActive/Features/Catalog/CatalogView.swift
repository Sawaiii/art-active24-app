import SwiftUI

@MainActor
@Observable
final class CatalogViewModel {
    private(set) var state: ViewState<[CategoryNode]> = .loading
    @ObservationIgnored private let catalog: CatalogRepository

    init(catalog: CatalogRepository) {
        self.catalog = catalog
    }

    func load() async {
        if state.content == nil { state = .loading }
        do {
            let tree = try await catalog.tree()
            state = tree.isEmpty ? .empty : .content(tree)
        } catch {
            guard !error.isCancellation else { return }
            if state.content == nil { state = .error(error.userMessage) }
        }
    }
}

/// Куда ведёт узел меню.
enum CatalogNavigation {
    static func route(for node: CategoryNode, preferChildren: Bool = true) -> CatalogDestination {
        switch node.kind {
        case .venues:
            return .route(.venues(collectionId: node.id == venuesRootId ? nil : node.id, title: node.name))
        case .landing, .scenario:
            if let url = node.url?.resolvedURL { return .web(url) }
            return .route(.category(id: node.id, title: node.name))
        case .catalog, .buy, .unknown:
            if preferChildren, node.hasChildren { return .route(.catalogLevel(node)) }
            return .route(.category(id: node.id, title: node.name))
        }
    }

    /// Корень «Площадки» на сайте — раздел 676.
    static let venuesRootId = 676
}

enum CatalogDestination {
    case route(Route)
    case web(URL)
}

/// Каталог — первый уровень меню «Услуги» с иконками.
struct CatalogView: View {
    @State private var viewModel: CatalogViewModel
    @Environment(Router.self) private var router

    init(viewModel: CatalogViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ListSkeleton(rows: 10).padding(Spacing.gutter)
                Spacer()
            case let .error(message):
                ErrorStateView(message: message) { await viewModel.load() }
            case .empty:
                EmptyStateView(systemImage: "square.grid.2x2", title: String(localized: "Каталог пока пуст"))
            case let .content(nodes):
                CategoryList(nodes: nodes, allNode: nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.catalogPage)
        .navigationTitle(Text("Каталог"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.search) } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel(Text("Поиск"))
            }
        }
        .refreshable { await viewModel.load() }
        .task { if viewModel.state.content == nil { await viewModel.load() } }
    }
}

/// Уровни 2–3: «Все …» + подразделы.
struct CatalogLevelView: View {
    let node: CategoryNode

    var body: some View {
        CategoryList(nodes: node.childNodes, allNode: node)
            .background(Palette.catalogPage)
            .navigationTitle(Text(node.name))
            .navigationBarTitleDisplayMode(.large)
    }
}

private struct CategoryList: View {
    let nodes: [CategoryNode]
    let allNode: CategoryNode?
    @Environment(Router.self) private var router

    var body: some View {
        List {
            if let allNode {
                Button { open(allNode, preferChildren: false) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Palette.accentTint10))
                        Text("Все: \(allNode.name)")
                            .font(BrandFont.golos(16, .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }
            }
            ForEach(nodes) { node in
                Button { open(node, preferChildren: true) } label: {
                    CategoryRow(node: node)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func open(_ node: CategoryNode, preferChildren: Bool) {
        Haptics.play(.selection)
        switch CatalogNavigation.route(for: node, preferChildren: preferChildren) {
        case let .route(route): router.push(route)
        case let .web(url): router.openWeb(url)
        }
    }
}

private struct CategoryRow: View {
    let node: CategoryNode

    var body: some View {
        HStack(spacing: 14) {
            CategoryIcon(node: node)
            Text(node.name)
                .font(BrandFont.golos(16, .medium))
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if node.hasChildren || node.kind == .venues {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.disabled)
            } else if node.kind == .landing || node.kind == .scenario {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.disabled)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Иконка раздела: растровая картинка с сервера, иначе SF Symbol по смыслу
/// (SVG-иконки меню сайта ImageIO не рисует).
struct CategoryIcon: View {
    let node: CategoryNode

    var body: some View {
        Group {
            if let url = rasterURL {
                RemoteImage(url: url, maxPixel: 120, placeholder: Palette.accentTint10)
            } else {
                Image(systemName: CategorySymbols.symbol(for: node.name))
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.accentTint10)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var rasterURL: URL? {
        for raw in [node.image, node.icon] {
            if let url = raw?.resolvedURL, url.pathExtension.lowercased() != "svg" { return url }
        }
        return nil
    }
}

/// SF Symbols, близкие к иконкам меню сайта.
enum CategorySymbols {
    private static let table: [(String, String)] = [
        ("кейтеринг", "fork.knife"), ("казино", "suit.spade"), ("фотозон", "camera"),
        ("мастер", "paintpalette"), ("квиз", "questionmark.bubble"), ("мебел", "sofa"),
        ("декор", "sparkles"), ("шатр", "tent"), ("аттракцион", "balloon.2"),
        ("площадк", "building.2"), ("сцен", "music.mic"), ("подиум", "music.mic"),
        ("оборудован", "hifispeaker.2"), ("тимбилдинг", "person.3"), ("персонал", "person.badge.shield.checkmark"),
        ("праздник", "gift"), ("гардероб", "hanger"), ("бар", "wineglass"), ("vr", "visionpro"),
        ("обогрев", "flame"), ("свет", "lightbulb"), ("звук", "speaker.wave.2"),
    ]

    static func symbol(for name: String) -> String {
        let lower = name.lowercased()
        return table.first { lower.contains($0.0) }?.1 ?? "square.grid.2x2"
    }
}

#if DEBUG
#Preview("Каталог") {
    NavigationStack {
        CatalogView(viewModel: CatalogViewModel(catalog: PreviewRepositories.shared))
    }
    .previewEnvironment()
}
#endif
