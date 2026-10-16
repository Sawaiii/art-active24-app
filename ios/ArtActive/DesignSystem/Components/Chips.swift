import SwiftUI

/// Табы подкатегорий: белая плашка r16 h44, активный — фиолетовый текст.
struct ChipTabs<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    var selected: Item?
    let onSelect: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items, id: \.self) { item in
                    let isActive = item == selected
                    Button {
                        Haptics.play(.selection)
                        onSelect(item)
                    } label: {
                        Text(title(item))
                            .font(.aaChip)
                            .foregroundStyle(isActive ? Palette.accent : Palette.text)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surface))
    }
}

/// Пилюли-фильтры: серая подложка r980 p3, выбранная — белая.
struct PillSegment<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(items, id: \.self) { item in
                    let isActive = item == selection
                    Button {
                        guard item != selection else { return }
                        Haptics.play(.selection)
                        withAnimation(Motion.snappy(reduceMotion)) { selection = item }
                    } label: {
                        Text(title(item))
                            .font(BrandFont.inter(12, .medium, relativeTo: .caption))
                            .foregroundStyle(isActive ? Palette.textProduct : Palette.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if isActive {
                                    Capsule()
                                        .fill(Palette.surface)
                                        .brandShadow(.segmentActive)
                                        .matchedGeometryEffect(id: "pill", in: namespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Capsule().fill(Palette.segmented))
        }
    }
}

/// Отдельная пилюля-переключатель (фасеты, цвета, допы).
struct ToggleChip: View {
    let title: String
    var subtitle: String?
    var colorDot: Color?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.play(.selection)
            action()
        } label: {
            HStack(spacing: 6) {
                if let colorDot {
                    Circle()
                        .fill(colorDot)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                }
                Text(title)
                    .font(.aaChip)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.aaCaption)
                        .foregroundStyle(isOn ? Palette.accent.opacity(0.7) : Palette.muted2)
                }
            }
            .foregroundStyle(isOn ? Palette.accent : Palette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(isOn ? Palette.accentTint10 : Palette.surfaceMuted))
            .overlay(Capsule().strokeBorder(isOn ? Palette.accent : .clear, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.95))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Простые бейджи.
struct BadgeView: View {
    let text: String
    var background: Color = Palette.accent
    var foreground: Color = .white

    var body: some View {
        Text(text)
            .font(.pBadge)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(background))
    }
}

extension BadgeView {
    init(_ badge: Badge) {
        self.init(text: badge.text, background: Color(hexString: badge.color) ?? Palette.accent)
    }
}

/// Жёлтый бейдж срока «1 день».
struct DayBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.pBadgeBold)
            .tracking(0.24)
            .foregroundStyle(Palette.onYellow)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(Palette.dayBadge))
            .contentTransition(.numericText())
    }
}

/// «арт: 07138» — тап копирует.
struct ArticleBadge: View {
    let art: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = art
            Haptics.play(.selection)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Text(copied ? String(localized: "скопировано") : "арт: \(art)")
                .font(BrandFont.inter(12, relativeTo: .caption))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: Radius.article).fill(Palette.chipArticle))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Артикул \(art)"))
        .accessibilityHint(Text("Скопировать"))
    }
}

/// Счётчик в кружке (таб-бар, заголовок корзины).
struct CounterBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.aaCounter)
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .padding(.horizontal, count > 9 ? 4 : 0)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(Palette.accent))
    }
}
