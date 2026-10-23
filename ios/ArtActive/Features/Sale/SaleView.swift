import Observation
import SwiftUI

/// «Акции» — страница «Выгодные предложения» сайта (/sale/).
@MainActor
@Observable
final class SaleViewModel {
    private(set) var state: ViewState<[HomeItem]> = .loading
    private(set) var title: String?

    @ObservationIgnored private let repository: ContentRepository

    init(repository: ContentRepository) {
        self.repository = repository
    }

    func load() async {
        if state.content == nil { state = .loading }
        do {
            let sale = try await repository.sale()
            title = sale.title
            let items = (sale.items ?? []).filter { !($0.title ?? "").isEmpty }
            state = items.isEmpty ? .empty : .content(items)
        } catch {
            guard !error.isCancellation else { return }
            if state.content == nil { state = .error(error.userMessage) }
        }
    }
}

struct SaleView: View {
    @State private var viewModel: SaleViewModel
    @State private var offer: OfferSelection?

    init(viewModel: SaleViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sale.screen")
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, 32)
        }
        .background(Palette.catalogPage)
        .navigationTitle(Text(viewModel.title ?? String(localized: "Акции")))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            Haptics.play(.refresh)
            await viewModel.load()
        }
        .offerSheet($offer)
        .task { if viewModel.state.content == nil { await viewModel.load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ForEach(0..<3, id: \.self) { _ in OfferCardSkeleton() }
                .shimmering()
        case let .error(message):
            ErrorStateView(message: message) { await viewModel.load() }
                .padding(.top, 60)
        case .empty:
            EmptyStateView(
                systemImage: "tag",
                title: String(localized: "Сейчас акций нет"),
                message: String(localized: "Загляните позже — мы регулярно добавляем выгодные предложения")
            )
            .padding(.top, 60)
        case let .content(items):
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                OfferCard(item: item, placement: .full) {
                    offer = OfferSelection(index: index, item: item)
                }
                .accessibilityIdentifier("sale.offer.\(index)")
            }
        }
    }
}

// MARK: - Карточка и шит предложения

/// Выбранное предложение (у акций нет id — индекс в списке).
struct OfferSelection: Identifiable, Hashable {
    let index: Int
    let item: HomeItem
    var id: Int { index }
}

/// Карточка «Выгодного предложения»: фото 710×446, метка («Бонус»), заголовок, текст.
struct OfferCard: View {
    enum Placement {
        /// Лента главной: фиксированная ширина, текст в 3 строки.
        case rail
        /// Список «Акций»: во всю ширину.
        case full
    }

    let item: HomeItem
    var placement: Placement = .rail
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                RemoteImage(url: item.image?.resolvedURL, maxPixel: placement == .rail ? 700 : 1000)
                    .aspectRatio(MediaAspect.offer, contentMode: .fit)
                    .overlay(alignment: .topLeading) {
                        if let badge = item.badge, !badge.isEmpty {
                            BadgeView(text: badge, background: Palette.saleYellow, foreground: Palette.onYellow)
                                .padding(10)
                        }
                    }
                    .clipped()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title ?? "")
                        .font(BrandFont.golos(17, .semibold, relativeTo: .headline))
                        .foregroundStyle(Palette.textProduct)
                        .multilineTextAlignment(.leading)
                        // В ленте место под строки резервируется — карточки одной высоты.
                        .lineLimit(2, reservesSpace: placement == .rail)
                    if let text = item.subtitle, !text.isEmpty {
                        Text(text)
                            .font(.aaBodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(placement == .rail ? 3 : 4, reservesSpace: placement == .rail)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityHint(Text("Подробнее об акции"))
    }

    private var accessibilityText: String {
        [item.badge, item.title, item.subtitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

/// Подробности предложения: фото, метка, полный текст; «Воспользоваться» — заявка менеджеру,
/// ниже — кнопки связи (звонок, мессенджеры).
struct OfferSheet: View {
    let item: HomeItem
    let onRequest: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RemoteImage(url: item.image?.resolvedURL, maxPixel: 1200)
                        .aspectRatio(MediaAspect.offer, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                        .accessibilityHidden(true)
                    if let badge = item.badge, !badge.isEmpty {
                        BadgeView(text: badge, background: Palette.saleYellow, foreground: Palette.onYellow)
                    }
                    Text(item.title ?? "")
                        .font(.aaPageTitle)
                        .foregroundStyle(Palette.textProduct)
                        .accessibilityAddTraits(.isHeader)
                    if let text = item.subtitle, !text.isEmpty {
                        Text(text)
                            .font(.aaBody)
                            .foregroundStyle(Palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button(action: onRequest) {
                        Text("Воспользоваться предложением")
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 52, radius: Radius.md, font: .aaSubmit))
                    .accessibilityIdentifier("offer.request")
                    .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Остались вопросы?")
                            .font(.pH3)
                            .foregroundStyle(Palette.textProduct)
                            .accessibilityAddTraits(.isHeader)
                        ContactButtonsRow()
                    }
                    .padding(.top, 8)
                }
                .padding(Spacing.gutterProduct)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("offer.sheet")
            }
            .background(Palette.page)
            .navigationTitle(Text("Акция"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Закрыть"))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct OfferCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle()
                .fill(Palette.bgTertiary.opacity(0.7))
                .aspectRatio(MediaAspect.offer, contentMode: .fit)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(height: 18)
                SkeletonBlock(width: 220, height: 14)
            }
            .padding(14)
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Показ шита и заявка

extension View {
    /// Шит предложения. «Воспользоваться» закрывает шит и после этого открывает форму заявки
    /// (через вход, если нужно) — модальные окна не громоздятся друг на друга.
    func offerSheet(_ selection: Binding<OfferSelection?>) -> some View {
        modifier(OfferSheetModifier(selection: selection))
    }
}

private struct OfferSheetModifier: ViewModifier {
    @Binding var selection: OfferSelection?
    @State private var pending: RequestSubject?
    @State private var request: RequestSubject?
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content
            .sheet(item: $selection, onDismiss: presentPendingRequest) { offer in
                OfferSheet(item: offer.item) {
                    let title = offer.item.title ?? ""
                    pending = RequestSubject(
                        kind: .callback,
                        title: String(localized: "Акция «\(title)»"),
                        comment: String(localized: "Хочу воспользоваться акцией «\(title)»")
                    )
                    selection = nil
                }
            }
            .sheet(item: $request) { subject in
                RequestFormSheet(viewModel: RequestFormViewModel(subject: subject, orders: env.orders))
            }
    }

    private func presentPendingRequest() {
        guard let subject = pending else { return }
        pending = nil
        env.router.requireLogin(isLoggedIn: env.auth.isLoggedIn) { request = subject }
    }
}

#if DEBUG
#Preview("Акции") {
    NavigationStack {
        SaleView(viewModel: SaleViewModel(repository: PreviewRepositories.shared))
    }
    .previewEnvironment()
}
#endif
