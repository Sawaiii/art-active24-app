import SwiftUI

/// «Примеры работ» — все кейсы с рубриками (как /cases/ сайта).
struct CasesView: View {
    @State private var viewModel: CasesViewModel
    @Environment(Router.self) private var router

    init(viewModel: CasesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                content
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cases.screen")
            .padding(.horizontal, Spacing.gutter)
            .padding(.bottom, 32)
        }
        .background(Palette.catalogPage)
        .navigationTitle(Text(viewModel.title ?? String(localized: "Кейсы")))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            Haptics.play(.refresh)
            await viewModel.load()
        }
        .task { if viewModel.allItems.isEmpty { await viewModel.load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ForEach(0..<3, id: \.self) { _ in CaseCardSkeleton() }
                .shimmering()
        case let .error(message):
            ErrorStateView(message: message) { await viewModel.load() }
                .padding(.top, 60)
        case .empty:
            EmptyStateView(systemImage: "photo.on.rectangle.angled", title: String(localized: "Кейсов пока нет"))
                .padding(.top, 60)
        case .content:
            if viewModel.categories.count > 1 {
                ChipTabs(
                    items: viewModel.chipIds,
                    title: { id in viewModel.categoryName(id) ?? String(localized: "Все кейсы") },
                    selected: viewModel.selectedCategoryId,
                    onSelect: { id in
                        withAnimation(.snappy) { viewModel.selectedCategoryId = id }
                    }
                )
                .accessibilityIdentifier("cases.categories")
            }
            ForEach(viewModel.items) { item in
                CaseCard(item: item, categoryName: viewModel.categoryName(item.categoryId)) {
                    router.push(.caseStudy(slug: item.slug, title: item.title))
                }
            }
        }
    }
}

/// Плитка кейса: обложка 16:9, рубрика, название, бюджет и число гостей (как карточка /cases/).
struct CaseCard: View {
    let item: CaseSummary
    var categoryName: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                RemoteImage(url: item.image?.resolvedURL, maxPixel: 900)
                    .aspectRatio(MediaAspect.caseCover, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    if let categoryName {
                        Text(categoryName).font(.aaCaption).foregroundStyle(Palette.accent)
                    }
                    Text(item.title)
                        .font(BrandFont.golos(17, .semibold, relativeTo: .headline))
                        .foregroundStyle(Palette.textProduct)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    CaseFactsLine(budget: item.budget, guests: item.guests)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous).fill(Palette.surface))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("case.card.\(item.slug)")
    }
}

/// «300 000 ₽ · 100 гостей» со значками, как подпись карточки кейса на сайте.
struct CaseFactsLine: View {
    let budget: String?
    let guests: Int?

    var body: some View {
        if budget != nil || guests != nil {
            HStack(spacing: 12) {
                if let budget {
                    Label {
                        Text(budget)
                    } icon: {
                        Image(systemName: "banknote")
                    }
                }
                if let guests {
                    Label {
                        Text(String(localized: "Гостей: \(Money.digits(guests))"))
                    } icon: {
                        Image(systemName: "person.2")
                    }
                }
            }
            .font(.aaBodySmall)
            .foregroundStyle(Palette.textSecondary)
            .labelStyle(CompactLabelStyle())
        }
    }
}

/// Значок + текст вплотную (системный Label даёт слишком широкий отступ для подписи).
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.accessibilityHidden(true)
            configuration.title
        }
    }
}

private struct CaseCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.bgTertiary.opacity(0.7))
                .aspectRatio(MediaAspect.caseCover, contentMode: .fit)
            SkeletonBlock(width: 80, height: 12)
            SkeletonBlock(height: 18)
            SkeletonBlock(width: 180, height: 14)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous).fill(Palette.surface))
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Кейсы") {
    NavigationStack {
        CasesView(viewModel: CasesViewModel(categoryId: nil, repository: PreviewRepositories.shared))
    }
    .previewEnvironment()
}
#endif
