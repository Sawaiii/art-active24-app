import SwiftUI

/// Кнопка площадок МК (аватары залов + «3 площадки») → шит со справочником залов.
struct MasterclassVenuesButton: View {
    let masterclass: Masterclass
    @State private var isPresented = false

    private var venues: [MasterclassVenue] { masterclass.venues ?? [] }

    var body: some View {
        if !venues.isEmpty {
            Button {
                Haptics.play(.selection)
                isPresented = true
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: -10) {
                        ForEach(Array(venues.prefix(3).enumerated()), id: \.offset) { _, venue in
                            RemoteImage(url: venue.images?.first?.resolvedURL, maxPixel: 120)
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(masterclass.venueTitle ?? String(localized: "Где проходит"))
                            .font(BrandFont.inter(14, .semibold))
                            .foregroundStyle(Palette.textProduct)
                        Text("\(venues.count) площадок")
                            .font(.pStepLabel)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.disabled)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
            }
            .buttonStyle(PressableStyle(scale: 0.98))
            .accessibilityIdentifier("mk.venues")
            .sheet(isPresented: $isPresented) {
                MasterclassVenuesSheet(masterclass: masterclass)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct MasterclassVenuesSheet: View {
    let masterclass: Masterclass
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let text = masterclass.venueText, !text.isEmpty {
                        Text(text)
                            .font(.pBody)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    ForEach(Array((masterclass.venues ?? []).enumerated()), id: \.offset) { _, venue in
                        VStack(alignment: .leading, spacing: 10) {
                            let photos = GalleryItem.from(urls: venue.images ?? [])
                            if !photos.isEmpty {
                                GalleryPager(items: photos, aspectRatio: 4 / 3, cornerRadius: Radius.card, imageBackground: Palette.imagePlaceholder)
                            }
                            Text(venue.name ?? "")
                                .font(.pH3)
                                .foregroundStyle(Palette.textProduct)
                            if let text = venue.text, !text.isEmpty {
                                Text(text)
                                    .font(.pBody)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                }
                .padding(Spacing.gutterProduct)
            }
            .navigationTitle(Text(masterclass.venueTitle ?? String(localized: "Площадки")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                        .accessibilityIdentifier("mk.venues.done")
                }
            }
        }
    }
}

/// «Как проходит» / «Что включено» — табы.
struct MasterclassInfoSection: View {
    let masterclass: Masterclass

    enum Tab: Hashable { case steps, included }
    @State private var tab: Tab = .steps

    private var tabs: [Tab] {
        var result: [Tab] = []
        if !(masterclass.steps ?? []).isEmpty { result.append(.steps) }
        if !(masterclass.included ?? []).isEmpty { result.append(.included) }
        return result
    }

    var body: some View {
        if !tabs.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                if tabs.count > 1 {
                    PillSegment(items: tabs, title: title(for:), selection: $tab)
                } else {
                    Text(title(for: tabs[0]))
                        .font(.pH3)
                        .foregroundStyle(Palette.textProduct)
                }
                switch tabs.count > 1 ? tab : tabs[0] {
                case .steps:
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array((masterclass.steps ?? []).enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text(verbatim: String(format: "%02d", index + 1))
                                    .font(BrandFont.inter(13, .bold))
                                    .foregroundStyle(Palette.accent)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Palette.accentTint10))
                                VStack(alignment: .leading, spacing: 4) {
                                    if let title = step.title {
                                        Text(title)
                                            .font(BrandFont.inter(15, .semibold))
                                            .foregroundStyle(Palette.textProduct)
                                    }
                                    if let text = step.text {
                                        Text(text)
                                            .font(.pBody)
                                            .foregroundStyle(Palette.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                case .included:
                    BulletList(title: masterclass.includedTitle ?? String(localized: "Что включено"), items: masterclass.included ?? [])
                }
            }
            .onAppear { if !tabs.contains(tab), let first = tabs.first { tab = first } }
        }
    }

    private func title(for tab: Tab) -> String {
        switch tab {
        case .steps: return masterclass.stepsTitle ?? String(localized: "Как проходит")
        case .included: return masterclass.includedTitle ?? String(localized: "Что включено")
        }
    }
}

/// «Похожие мастер-классы» и теги «Мастер-классы по темам».
struct MasterclassRelatedSection: View {
    let masterclass: Masterclass
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let related = masterclass.related, !related.isEmpty {
                SimilarSection(title: masterclass.relatedTitle ?? String(localized: "Похожие мастер-классы"), products: related)
            }
            if let tags = masterclass.tags, !tags.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Мастер-классы по темам")
                        .font(.pH3)
                        .foregroundStyle(Palette.textProduct)
                    FlowLayout {
                        ForEach(tags) { tag in
                            ToggleChip(title: tag.name, isOn: false) {
                                router.push(.category(id: tag.id, title: tag.name))
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutterProduct)
            }
        }
    }
}
