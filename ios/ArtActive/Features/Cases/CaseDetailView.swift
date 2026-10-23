import SwiftUI

/// Карточка кейса (как /cases/{slug}/ сайта): галерея 4:3, рубрика и название, факты
/// (бюджет, гости, рубрика), «Задача» и «Решение», «Что было на мероприятии» (товары и разделы),
/// заявка «Хочу так же», связь с менеджером, похожие кейсы.
struct CaseDetailView: View {
    @State private var viewModel: CaseDetailViewModel
    @State private var request: RequestSubject?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(viewModel: CaseDetailViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                CaseDetailSkeleton()
            case let .error(message):
                ErrorStateView(message: message) { await viewModel.load() }
            case .empty:
                // Данных кейса нет — остаётся страница сайта.
                EmptyStateView(
                    systemImage: "photo.on.rectangle.angled",
                    title: String(localized: "Кейс не найден"),
                    message: String(localized: "Возможно, он есть на сайте"),
                    actionTitle: viewModel.siteURL == nil ? nil : String(localized: "Открыть на сайте")
                ) {
                    if let url = viewModel.siteURL { env.router.openWeb(url) }
                }
            case let .content(study):
                content(study)
            }
        }
        .background(Palette.page)
        .topScrollFade(Palette.page)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = viewModel.state.content?.shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel(Text("Поделиться"))
                }
            }
        }
        .sheet(item: $request) { subject in
            RequestFormSheet(viewModel: RequestFormViewModel(subject: subject, orders: env.orders))
        }
        .task { if viewModel.state.content == nil { await viewModel.load() } }
    }

    private func content(_ study: CaseStudy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionLarge) {
                let gallery = GalleryItem.from(study.media ?? [])
                if !gallery.isEmpty {
                    // Фото кейсов 800×600 — 4:3; подложка видна, пока фото грузится.
                    GalleryPager(items: gallery, aspectRatio: MediaAspect.photo, imageBackground: Palette.imagePlaceholder)
                } else if let cover = study.image?.resolvedURL {
                    RemoteImage(url: cover, maxPixel: 1200)
                        .aspectRatio(MediaAspect.caseCover, contentMode: .fit)
                        .accessibilityHidden(true)
                }

                header(study).padding(.horizontal, Spacing.gutterProduct)

                facts(study).padding(.horizontal, Spacing.gutterProduct)

                ForEach(Array((study.sections ?? []).enumerated()), id: \.offset) { _, section in
                    DescriptionSection(html: section.html, title: section.title)
                        .padding(.horizontal, Spacing.gutterProduct)
                }

                whatWasThere(study)

                requestCard(study).padding(.horizontal, Spacing.gutterProduct)

                ManagerContactSection().padding(.horizontal, Spacing.gutterProduct)

                if let similar = study.similar, !similar.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: String(localized: "Похожие кейсы"))
                            .padding(.horizontal, Spacing.gutterProduct)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(similar) { item in
                                    CaseCard(item: item) {
                                        env.router.push(.caseStudy(slug: item.slug, title: item.title))
                                    }
                                    .frame(width: 280)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, Spacing.gutterProduct)
                        }
                        .scrollTargetBehavior(.viewAligned)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("case.similar")
                }
            }
            .padding(.bottom, Spacing.sectionLarge)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("case.detail")
        }
    }

    private func header(_ study: CaseStudy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name = study.category?.name {
                Text(name).font(.aaCaption).foregroundStyle(Palette.accent)
            }
            Text(study.title)
                .font(.aaPageTitle)
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
            if let description = study.description, !description.isEmpty {
                Text(description)
                    .font(.pBody)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func facts(_ study: CaseStudy) -> some View {
        if study.budget != nil || study.guests != nil || study.category != nil {
            // На крупных размерах шрифта плитки встают в столбец, иначе подписи ломаются по буквам.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                if let budget = study.budget {
                    fact(value: budget, title: String(localized: "бюджет"))
                }
                if let guests = study.guests {
                    fact(value: Money.digits(guests), title: String(localized: "гостей"))
                }
                if let category = study.category?.name {
                    fact(value: category, title: String(localized: "направление"))
                }
            }
        }
    }

    private func fact(value: String, title: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(BrandFont.golos(17, .bold, relativeTo: .headline))
                .foregroundStyle(Palette.textProduct)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(title).font(.aaCaption).foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
        .accessibilityElement(children: .combine)
    }

    /// «Что было на мероприятии»: товары — лентой плиток, остальное (разделы, страницы) — чипами.
    @ViewBuilder
    private func whatWasThere(_ study: CaseStudy) -> some View {
        let products = study.products ?? []
        let links = study.links ?? []
        if !products.isEmpty || !links.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Что было на мероприятии")
                    .font(.pSection)
                    .tracking(-0.6)
                    .foregroundStyle(Palette.textProduct)
                    .padding(.horizontal, Spacing.gutterProduct)
                    .accessibilityAddTraits(.isHeader)
                if !products.isEmpty {
                    ProductRail(products: products)
                }
                if !links.isEmpty {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                            CaseLinkChip(link: link) { open(link) }
                        }
                    }
                    .padding(.horizontal, Spacing.gutterProduct)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("case.products")
        }
    }

    private func open(_ link: CaseLink) {
        Haptics.play(.selection)
        if let id = link.categoryId {
            env.router.push(.category(id: id, title: link.title))
        } else if let url = link.url.resolvedURL {
            env.router.openWeb(url)
        }
    }

    /// Градиентная плашка «Хочу так же» (кнопка карточки кейса на сайте).
    private func requestCard(_ study: CaseStudy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Хотите так же?")
                .font(BrandFont.golos(22, .bold, relativeTo: .title2))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text("Расскажите о вашем мероприятии — менеджер подберёт программу и рассчитает бюджет.")
                .font(.aaBodySmall)
                .foregroundStyle(.white.opacity(0.92))
            Button {
                let subject = RequestSubject(
                    kind: .callback,
                    title: String(localized: "Кейс «\(study.title)»"),
                    comment: String(localized: "Хочу так же, как в кейсе «\(study.title)»")
                )
                env.router.requireLogin(isLoggedIn: env.auth.isLoggedIn) { request = subject }
            } label: {
                Text("Хочу так же")
                    .font(.aaSubmit)
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(.white))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("case.request")
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.leadGradient))
    }
}

/// Чип позиции «Что было на мероприятии» без карточки товара: миниатюра + название.
private struct CaseLinkChip: View {
    let link: CaseLink
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RemoteImage(url: link.image?.resolvedURL, maxPixel: 120)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                Text(link.title)
                    .font(.aaChip)
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if link.categoryId == nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.disabled)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(minHeight: 44)
            .background(Capsule().fill(Palette.surfaceMuted))
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(link.categoryId == nil ? Text("Откроется страница сайта") : Text(""))
    }
}

/// Скелетон карточки кейса: галерея 4:3, рубрика/название, плитки фактов, текст.
private struct CaseDetailSkeleton: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                Rectangle()
                    .fill(Palette.bgTertiary.opacity(0.6))
                    .aspectRatio(MediaAspect.photo, contentMode: .fit)
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonBlock(width: 80, height: 12)
                    SkeletonBlock(height: 24)
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            SkeletonBlock(height: 64, radius: Radius.md)
                        }
                    }
                    .padding(.top, 6)
                    SkeletonBlock(width: 120, height: 18).padding(.top, 10)
                    SkeletonBlock(height: 14)
                    SkeletonBlock(height: 14)
                    SkeletonBlock(width: 220, height: 14)
                }
                .padding(.horizontal, Spacing.gutterProduct)
            }
            .shimmering()
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Загрузка"))
    }
}

#if DEBUG
#Preview("Кейс") {
    NavigationStack {
        CaseDetailView(viewModel: CaseDetailViewModel(slug: "keytering-ng", initialTitle: nil, repository: PreviewRepositories.shared))
    }
    .previewEnvironment()
}
#endif
