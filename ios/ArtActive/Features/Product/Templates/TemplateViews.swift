import SwiftUI

// MARK: - Шаблон 88 «простая»

/// Список комплектов (состав, цена+единица), переключатель «в корзину» на комплект, допы.
struct SimpleProductView: View {
    let product: Product
    @Environment(CartStore.self) private var cart

    var body: some View {
        ToggleTemplateBody(product: product, viewModel: ToggleOrderViewModel(product: product, cart: cart), style: .simple)
    }
}

// MARK: - Шаблон 81 «сложная»

/// Промо-шапка, «что это», видео, «было круто», комплекты (в комплекте / требования), группы допов.
struct ShowcaseProductView: View {
    let product: Product
    @Environment(CartStore.self) private var cart

    var body: some View {
        ToggleTemplateBody(product: product, viewModel: ToggleOrderViewModel(product: product, cart: cart), style: .showcase)
    }
}

private struct ToggleTemplateBody: View {
    enum Style { case simple, showcase }

    let product: Product
    @State private var viewModel: ToggleOrderViewModel
    let style: Style
    @State private var request: RequestSubject?
    @State private var extrasGroup = ""
    @Environment(AppEnvironment.self) private var env

    init(product: Product, viewModel: ToggleOrderViewModel, style: Style) {
        self.product = product
        _viewModel = State(initialValue: viewModel)
        self.style = style
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if style == .showcase {
                    PromoHeader(product: product) { order(complect: nil) }
                } else {
                    GalleryPager(items: GalleryItem.from(product.media), badge: product.badge)
                    ProductTitleRow(product: product)
                        .padding(.horizontal, Spacing.gutterProduct)
                }

                if style == .showcase, let blocks = product.blocks, !blocks.isEmpty {
                    ContentBlocksView(blocks: blocks)
                }

                complectsSection
                extrasSection

                VStack(alignment: .leading, spacing: 26) {
                    if let specs = product.specs, !specs.isEmpty { SpecsSection(specs: specs) }
                    if let html = product.descriptionHtml, !html.isEmpty { DescriptionSection(html: html) }
                }
                .padding(.horizontal, Spacing.gutterProduct)

                if let similar = product.similar, !similar.isEmpty {
                    SimilarSection(title: String(localized: "Похожие позиции"), products: similar)
                }
                ManagerContactSection().padding(.horizontal, Spacing.gutterProduct)
            }
            .padding(.bottom, 32)
        }
        .sheet(item: $request) { subject in
            RequestFormSheet(viewModel: RequestFormViewModel(subject: subject, orders: env.orders))
        }
    }

    private var complectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(product.complectsLabel ?? String(localized: "Комплекты"))
                .font(.pSection)
                .tracking(-0.6)
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
            ForEach(product.complects) { complect in
                ToggleComplectCard(
                    complect: complect,
                    priceText: viewModel.priceText(for: complect),
                    hint: viewModel.hint(for: complect),
                    isInCart: viewModel.isInCart(complect),
                    onToggle: { viewModel.toggle(complect) },
                    onOrder: { order(complect: complect) }
                )
            }
        }
        .padding(.horizontal, Spacing.gutterProduct)
    }

    @ViewBuilder
    private var extrasSection: some View {
        if !viewModel.options.isEmpty {
            let groups = viewModel.extraGroups
            VStack(alignment: .leading, spacing: 14) {
                Text(style == .simple ? String(localized: "Также подходит") : String(localized: "Дополнительно"))
                    .font(.pSection)
                    .tracking(-0.6)
                    .foregroundStyle(Palette.textProduct)
                    .padding(.horizontal, Spacing.gutterProduct)
                if groups.count > 1 {
                    PillSegment(
                        items: groups,
                        title: { $0.isEmpty ? String(localized: "Основное") : $0 },
                        selection: Binding(
                            get: { groups.contains(extrasGroup) ? extrasGroup : (groups.first ?? "") },
                            set: { extrasGroup = $0 }
                        )
                    )
                    .padding(.horizontal, Spacing.gutterProduct)
                }
                VStack(spacing: 8) {
                    let current = groups.count > 1 ? (groups.contains(extrasGroup) ? extrasGroup : groups.first) : nil
                    ForEach(viewModel.extras(in: current)) { extra in
                        ToggleExtraRow(extra: extra, isOn: viewModel.isInCart(extra: extra.id)) {
                            viewModel.toggleOption(extra.id)
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutterProduct)
                Text("Опции кладутся в корзину отдельной позицией.")
                    .font(.pPriceHint)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.gutterProduct)
            }
        }
    }

    private func order(complect: Complect?) {
        let subject = RequestSubject(
            kind: .product,
            title: complect.map { "\(product.name) — «\($0.title)»" } ?? product.name,
            productId: product.id,
            complectId: complect?.id
        )
        env.router.requireLogin(isLoggedIn: env.auth.isLoggedIn) { request = subject }
    }
}

/// Карточка комплекта шаблонов 88/81.
private struct ToggleComplectCard: View {
    let complect: Complect
    let priceText: String
    let hint: String?
    let isInCart: Bool
    let onToggle: () -> Void
    let onOrder: () -> Void

    @State private var showIncludes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let image = complect.image?.resolvedURL {
                    RemoteImage(url: image, maxPixel: 300)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(complect.title)
                        .font(BrandFont.inter(16, .semibold))
                        .foregroundStyle(Palette.textProduct)
                    if let subtitle = complect.subtitle {
                        Text(subtitle).font(.pStepLabel).foregroundStyle(Palette.textSecondary)
                    }
                    Text(priceText)
                        .font(BrandFont.inter(16, .bold))
                        .foregroundStyle(Palette.textProduct)
                    if let hint {
                        Text(hint).font(.pPriceHint).foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            let includes = complect.includes ?? []
            let requirements = complect.requirements ?? []
            if !includes.isEmpty || !requirements.isEmpty {
                DisclosureGroup(isExpanded: $showIncludes.animation()) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !includes.isEmpty { BulletList(title: String(localized: "В комплекте"), items: includes) }
                        if !requirements.isEmpty {
                            BulletList(title: String(localized: "Требования к помещению"), items: requirements, systemImage: "exclamationmark.circle")
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Состав и требования")
                        .font(BrandFont.inter(14, .medium))
                        .foregroundStyle(Palette.accent)
                }
                .tint(Palette.accent)
            }

            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Label {
                        Text(isInCart ? "В корзине" : "В корзину")
                    } icon: {
                        Image(systemName: isInCart ? "checkmark" : "cart.badge.plus")
                    }
                    .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PrimaryButtonStyle(height: 46, radius: Radius.md, font: .pCartButton, shadow: false))
                .opacity(isInCart ? 0.85 : 1)
                .accessibilityAddTraits(isInCart ? .isSelected : [])
                .accessibilityIdentifier("toggle.complect.\(complect.id)")

                Button("Заказать", action: onOrder)
                    .buttonStyle(SecondaryButtonStyle(height: 46, fill: Palette.surfaceMuted))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(isInCart ? Palette.accentTint05 : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isInCart ? Palette.accent.opacity(0.6) : Palette.border, lineWidth: 1)
        )
        .animation(.snappy, value: isInCart)
    }
}

private struct ToggleExtraRow: View {
    let extra: Extra
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RemoteImage(url: extra.image?.resolvedURL, maxPixel: 160)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(extra.name)
                        .font(BrandFont.inter(14, .semibold))
                        .foregroundStyle(Palette.textProduct)
                        .multilineTextAlignment(.leading)
                    if let note = extra.note {
                        Text(note).font(.pPriceHint).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.leading)
                    }
                    Text(extra.from == true ? String(localized: "от \(Money.rub(extra.price))") : Money.rub(extra.price))
                        .font(.pVariantPrice)
                        .foregroundStyle(Palette.variantPrice)
                }
                Spacer(minLength: 8)
                Label {
                    Text(isOn ? "В корзине" : "В корзину")
                } icon: {
                    Image(systemName: isOn ? "checkmark" : "cart.badge.plus")
                }
                .font(BrandFont.inter(12, .semibold))
                .foregroundStyle(isOn ? Palette.onAccent : Palette.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(Capsule().fill(isOn ? Palette.accent : Palette.accentTint10))
                .contentTransition(.symbolEffect(.replace))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(isOn ? Palette.accentTint05 : Palette.surfaceMuted))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Промо-шапка (banner-new): фон-фото, крошки, h1, лид, цена, артикул, «Заказать».
private struct PromoHeader: View {
    let product: Product
    let onOrder: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: product.media.first?.posterURL ?? product.media.first?.resolvedURL, maxPixel: 1200)
                .frame(height: 420)
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text(product.name)
                    .font(BrandFont.golos(28, .semibold, relativeTo: .largeTitle))
                    .foregroundStyle(.white)
                if let lead = product.lead {
                    Text(lead).font(.aaBodySmall).foregroundStyle(.white.opacity(0.9))
                }
                HStack(spacing: 10) {
                    PriceTagView(tag: product.price, color: .white)
                    if let art = product.art { ArticleBadge(art: art) }
                }
                Button("Заказать", action: onOrder)
                    .buttonStyle(PrimaryButtonStyle(height: 48))
                    .frame(maxWidth: 220)
            }
            .padding(Spacing.gutterProduct)
        }
        .frame(height: 420)
        .clipped()
    }
}

// MARK: - Шаблон 123 «персонал»

/// Лид, ставка «от 1 000 ₽ / час», галерея, похожий персонал, кнопка «Заказать».
struct StaffProductView: View {
    let product: Product

    var body: some View {
        RequestTemplateBody(product: product) {
            GalleryPager(items: GalleryItem.from(product.media), badge: product.badge)
            VStack(alignment: .leading, spacing: 12) {
                ProductTitleRow(product: product)
                PriceTagView(tag: product.price, numberFont: .pPriceAmount, color: Palette.textProduct)
            }
            .padding(.horizontal, Spacing.gutterProduct)
        } similarTitle: {
            String(localized: "Похожий персонал")
        }
    }
}

// MARK: - Шаблон 118 «Тимбилдинг 2.0»

/// Контент-блоки: инфо-чипы, описание, навыки, этапы, фишки, тарифы, галерея.
struct ProgramProductView: View {
    let product: Product

    var body: some View {
        RequestTemplateBody(product: product) {
            ZStack(alignment: .bottomLeading) {
                if let video = product.media.first(where: { $0.type == .video })?.resolvedURL {
                    InlineVideoCard(url: video, poster: product.media.first?.posterURL, title: product.name)
                } else {
                    GalleryPager(items: GalleryItem.from(product.media), badge: product.badge)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ProductTitleRow(product: product)
                PriceTagView(tag: product.price, numberFont: .pPriceAmount, color: Palette.textProduct)
            }
            .padding(.horizontal, Spacing.gutterProduct)
        } similarTitle: {
            String(localized: "Может заинтересовать")
        }
    }
}

/// Общий каркас заявочных шаблонов: шапка, блоки, похожие, липкая кнопка «Заказать».
private struct RequestTemplateBody<Header: View>: View {
    let product: Product
    @ViewBuilder let header: Header
    let similarTitle: () -> String

    @State private var request: RequestSubject?
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if let blocks = product.blocks, !blocks.isEmpty {
                    ContentBlocksView(blocks: blocks) { tier in
                        order(title: [product.name, tier.title].compactMap { $0 }.joined(separator: " — "))
                    }
                }
                VStack(alignment: .leading, spacing: 26) {
                    if let specs = product.specs, !specs.isEmpty { SpecsSection(specs: specs) }
                    if let html = product.descriptionHtml, !html.isEmpty { DescriptionSection(html: html) }
                }
                .padding(.horizontal, Spacing.gutterProduct)
                if let similar = product.similar, !similar.isEmpty {
                    SimilarSection(title: similarTitle(), products: similar)
                }
                ManagerContactSection().padding(.horizontal, Spacing.gutterProduct)
            }
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Стоимость").font(.pPriceLabel).foregroundStyle(Palette.textSecondary)
                    Text(Money.tag(product.price))
                        .font(.pPriceAmount)
                        .foregroundStyle(Palette.textProduct)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
                Button("Заказать") { order(title: product.name) }
                    .buttonStyle(PrimaryButtonStyle(height: 54, radius: Radius.md, font: .pCartButton))
                    .frame(width: 150)
            }
            .padding(.horizontal, Spacing.gutterProduct)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .stickyBottomBarBackground()
        }
        .sheet(item: $request) { subject in
            RequestFormSheet(viewModel: RequestFormViewModel(subject: subject, orders: env.orders))
        }
    }

    private func order(title: String) {
        let subject = RequestSubject(kind: .product, title: title, productId: product.id, complectId: product.complects.first?.id)
        env.router.requireLogin(isLoggedIn: env.auth.isLoggedIn) { request = subject }
    }
}
