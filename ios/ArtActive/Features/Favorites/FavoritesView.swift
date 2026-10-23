import SwiftUI

/// Избранное: локально для гостя, синхронизируется после входа.
struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            if favorites.items.isEmpty {
                EmptyStateView(
                    systemImage: "heart",
                    title: String(localized: "В избранном пусто"),
                    message: String(localized: "Нажмите на сердечко на карточке, чтобы сохранить товар"),
                    actionTitle: String(localized: "Перейти в каталог")
                ) { router.selectedTab = .catalog }
                .padding(.top, 60)
            } else {
                ProductGridView(products: favorites.items)
                    .padding(Spacing.gutter)
                    .animation(.snappy, value: favorites.items)
            }
        }
        .background(Palette.catalogPage)
        .navigationTitle(Text("Избранное"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            Haptics.play(.refresh)
            await favorites.refreshFromServer()
        }
    }
}
