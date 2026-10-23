import SwiftUI

/// Типизированные блоки шаблонов showcase/staff/program: lead, text, facts, gallery,
/// video, cards, steps, tiers, links.
struct ContentBlocksView: View {
    let blocks: [ContentBlock]
    /// «Заказать» у тарифа (tiers).
    var onOrderTier: ((ContentBlockItem) -> Void)?
    /// Шаблон карточки — от него зависят пропорции исходников (программа: 900×600, видео 960×445).
    var template: ProductTemplate = .unknown

    private var galleryAspect: CGFloat { template == .program ? MediaAspect.wide : MediaAspect.photo }
    private var videoAspect: CGFloat { template == .program ? MediaAspect.programVideo : MediaAspect.photo }

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sectionLarge) {
            ForEach(Array(blocks.filter(Self.hasContent).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    /// Пустые блоки не рендерим: иначе остаётся пустой отступ между секциями.
    private static func hasContent(_ block: ContentBlock) -> Bool {
        let items = block.items ?? []
        switch block.type {
        case .lead, .text:
            return !(block.title ?? "").isEmpty || !(block.text ?? "").isEmpty
        case .gallery:
            return items.contains { $0.image != nil }
        case .video:
            return items.contains { $0.video?.resolvedURL != nil }
        case .facts, .cards, .steps, .tiers, .links:
            return !items.isEmpty
        case .unknown:
            return false
        }
    }

    @ViewBuilder
    private func blockView(_ block: ContentBlock) -> some View {
        switch block.type {
        case .lead:
            VStack(alignment: .leading, spacing: 8) {
                title(block.title)
                if let text = block.text {
                    Text(text)
                        .font(BrandFont.inter(17, .medium))
                        .foregroundStyle(Palette.textProduct)
                }
            }
            .padding(.horizontal, Spacing.gutterProduct)
        case .text:
            VStack(alignment: .leading, spacing: 12) {
                title(block.title)
                if let text = block.text {
                    if text.contains("<") {
                        HTMLText(html: text, collapsedHeight: 220)
                    } else {
                        Text(text)
                            .font(.pBody)
                            .foregroundStyle(Palette.textProduct)
                            .lineSpacing(4)
                    }
                }
            }
            .padding(.horizontal, Spacing.gutterProduct)
        case .facts:
            VStack(alignment: .leading, spacing: 12) {
                title(block.title)
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title ?? "")
                                .font(BrandFont.inter(15, .bold))
                                .foregroundStyle(Palette.textProduct)
                            if let subtitle = item.subtitle ?? item.text {
                                Text(subtitle)
                                    .font(.pStepLabel)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, Spacing.gutterProduct)
        case .gallery:
            let photos = GalleryItem.from(urls: (block.items ?? []).compactMap(\.image))
            if !photos.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    title(block.title).padding(.horizontal, Spacing.gutterProduct)
                    GalleryPager(items: photos, aspectRatio: galleryAspect, cornerRadius: Radius.card, imageBackground: Palette.imagePlaceholder)
                        .padding(.horizontal, Spacing.gutterProduct)
                }
            }
        case .video:
            VStack(alignment: .leading, spacing: 12) {
                title(block.title)
                ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { _, item in
                    if let url = item.video?.resolvedURL {
                        InlineVideoCard(url: url, poster: item.image?.resolvedURL, title: item.title, aspect: videoAspect)
                    }
                }
            }
            .padding(.horizontal, Spacing.gutterProduct)
        case .cards:
            VStack(alignment: .leading, spacing: 12) {
                title(block.title).padding(.horizontal, Spacing.gutterProduct)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(Self.mergedCards(block.items ?? []).enumerated()), id: \.offset) { _, item in
                            InfoCard(item: item) { open(item.link) }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Spacing.gutterProduct)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        case .steps:
            VStack(alignment: .leading, spacing: 16) {
                title(block.title)
                ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { index, item in
                    StepRow(index: index, item: item)
                }
            }
            .padding(.horizontal, Spacing.gutterProduct)
        case .tiers:
            VStack(alignment: .leading, spacing: 12) {
                title(block.title).padding(.horizontal, Spacing.gutterProduct)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { _, item in
                            TierCard(item: item) { onOrderTier?(item) }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Spacing.gutterProduct)
                }
                .scrollTargetBehavior(.viewAligned)
            }
        case .links:
            VStack(alignment: .leading, spacing: 12) {
                title(block.title)
                FlowLayout {
                    ForEach(Array((block.items ?? []).enumerated()), id: \.offset) { _, item in
                        ToggleChip(title: item.title ?? "", isOn: false) { open(item.link) }
                    }
                }
            }
            .padding(.horizontal, Spacing.gutterProduct)
        case .unknown:
            EmptyView()
        }
    }

    /// «Фишки и кастомизации»: на сайте текстовый элемент и следом фото — отдельные элементы.
    /// Текстовый берёт ближайший следующий элемент «только фото»; оставшиеся фото — свои карточки.
    static func mergedCards(_ items: [ContentBlockItem]) -> [ContentBlockItem] {
        var result: [ContentBlockItem] = []
        var index = 0
        while index < items.count {
            let item = items[index]
            let next = index + 1 < items.count ? items[index + 1] : nil
            if item.image == nil, item.title != nil || item.text != nil, let next, isImageOnly(next) {
                result.append(ContentBlockItem(
                    title: item.title, subtitle: item.subtitle, text: item.text, image: next.image,
                    video: item.video, price: item.price, rows: item.rows, link: item.link ?? next.link
                ))
                index += 2
            } else {
                result.append(item)
                index += 1
            }
        }
        return result
    }

    private static func isImageOnly(_ item: ContentBlockItem) -> Bool {
        item.image != nil && (item.title ?? "").isEmpty && (item.text ?? "").isEmpty && (item.subtitle ?? "").isEmpty
    }

    @ViewBuilder
    private func title(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.pSection)
                .tracking(-0.6)
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func open(_ link: String?) {
        guard let url = link?.resolvedURL else { return }
        if let host = url.host?.lowercased(), AppConfig.siteHosts.contains(host) {
            env.deepLinks.handle(url)
        } else {
            env.router.openWeb(url)
        }
    }
}

private struct InfoCard: View {
    let item: ContentBlockItem
    let action: () -> Void

    var body: some View {
        // Карточка без ссылки — просто контент, а не «недоступная» кнопка для VoiceOver.
        if item.link == nil {
            card
        } else {
            Button(action: action) { card }
                .buttonStyle(PressableStyle())
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = item.image?.resolvedURL {
                // Исходники ~квадратные (283×270, 299×299).
                AspectImage(url: image, aspect: MediaAspect.square, cornerRadius: Radius.md, maxPixel: 600)
                    .accessibilityHidden(true)
            }
            if let title = item.title {
                Text(title)
                    .font(BrandFont.inter(15, .semibold))
                    .foregroundStyle(Palette.textProduct)
                    .multilineTextAlignment(.leading)
            }
            if let text = item.text {
                Text(text)
                    .font(.pStepLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surfaceMuted))
        .accessibilityElement(children: .combine)
    }
}

private struct StepRow: View {
    let index: Int
    let item: ContentBlockItem
    /// Кружок с номером растёт вместе с Dynamic Type, чтобы цифры не обрезались.
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: String(format: "%02d", index + 1))
                .font(BrandFont.inter(14, .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: badgeSize, height: badgeSize)
                .background(Circle().fill(Palette.accentTint10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title ?? "")
                        .font(BrandFont.inter(15, .semibold))
                        .foregroundStyle(Palette.textProduct)
                    Spacer(minLength: 8)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.pPriceLabel)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                if let text = item.text {
                    Text(text)
                        .font(.pBody)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let image = item.image?.resolvedURL {
                    AspectImage(url: image, aspect: MediaAspect.wide, cornerRadius: Radius.md, maxPixel: 800)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Тариф программы: строки параметров, цена, «Заказать».
private struct TierCard: View {
    let item: ContentBlockItem
    let onOrder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let image = item.image?.resolvedURL {
                AspectImage(url: image, aspect: MediaAspect.tier, cornerRadius: Radius.md, maxPixel: 800)
            }
            Text(item.title ?? "")
                .font(.pH3)
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
            if let subtitle = item.subtitle {
                Text(subtitle).font(.pStepLabel).foregroundStyle(Palette.textSecondary)
            }
            ForEach(Array((item.rows ?? []).enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(.pStepLabel).foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 8)
                    Text(row.value).font(BrandFont.inter(13, .semibold)).foregroundStyle(Palette.textProduct)
                }
            }
            Spacer(minLength: 0)
            PriceTagView(tag: item.price, numberFont: .pPriceAmount, color: Palette.textProduct)
            Button("Заказать", action: onOrder)
                .buttonStyle(PrimaryButtonStyle(height: 44, radius: Radius.md, font: .pCartButton, shadow: false))
                // Несколько тарифов подряд: VoiceOver должен различать кнопки.
                .accessibilityLabel(Text(verbatim: "\(String(localized: "Заказать")) \(item.title ?? "")"))
        }
        .padding(16)
        .frame(width: 260, alignment: .topLeading)
        .frame(minHeight: 260)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surfaceMuted))
    }
}

/// Видео в карточке: постер с кнопкой ▶ → AVPlayerViewController на весь экран.
struct InlineVideoCard: View {
    let url: URL
    let poster: URL?
    var title: String?
    /// Пропорция постера: программа — 960×445, остальное — 4:3.
    var aspect: CGFloat = MediaAspect.photo
    @State private var isPlaying = false

    var body: some View {
        Button {
            Haptics.play(.selection)
            isPlaying = true
        } label: {
            ZStack {
                RemoteImage(url: poster, maxPixel: 1000, placeholder: Palette.bgTertiary)
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .brandGlass(in: Circle(), tint: .black.opacity(0.25))
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Text(verbatim: title.map { "\(String(localized: "Смотреть видео")): \($0)" } ?? String(localized: "Смотреть видео")))
        .fullScreenCover(isPresented: $isPlaying) {
            VideoScreen(url: url)
        }
    }
}
