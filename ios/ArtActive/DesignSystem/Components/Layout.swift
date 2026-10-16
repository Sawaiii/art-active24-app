import SwiftUI

/// Перенос элементов по строкам (чипы фасетов, теги).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, maxWidth)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, maxWidth)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// Заголовок секции с необязательной ссылкой «Все».
struct SectionHeader: View {
    let title: String
    var font: Font = .aaSectionTitle
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(font)
                .tracking(-0.36)
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(LinkButtonStyle())
            }
        }
    }
}

/// Шаг конфигуратора: точка + подпись «Комплекты», «Время аренды».
struct StepLabel: View {
    let title: String
    var trailing: AnyView?

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Palette.accentSoft).frame(width: 8, height: 8)
            Text(title)
                .font(.pStepLabel)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

/// Хлебные крошки «Главная › Мебель › Столы».
struct Breadcrumbs: View {
    let crumbs: [Crumb]
    var onSelect: ((Crumb) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.breadcrumb)
                            .accessibilityHidden(true)
                    }
                    Button {
                        onSelect?(crumb)
                    } label: {
                        Text(crumb.name)
                            .font(.aaBreadcrumb)
                            .foregroundStyle(index == crumbs.count - 1 ? Palette.textSecondary : Palette.breadcrumb)
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelect == nil)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Навигация по разделам"))
    }
}

/// Цена листинга: «от» 12 + число 18/500 + «₽» серым.
struct PriceTagView: View {
    let tag: PriceTag?
    var numberFont: Font = .aaCardPrice
    var color: Color = Palette.textStrong

    var body: some View {
        if let tag {
            if tag.onRequest == true {
                Text("по запросу")
                    .font(.aaCardPriceFrom)
                    .foregroundStyle(Palette.textSecondary)
            } else if let amount = tag.amount {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if tag.from == true {
                        Text("от").font(.aaCardPriceFrom).foregroundStyle(color)
                    }
                    Text(Money.digits(amount))
                        .font(numberFont)
                        .foregroundStyle(color)
                        .monospacedDigit()
                    Text(Money.currencySymbol)
                        .font(BrandFont.golos(18, .regular, relativeTo: .headline))
                        .foregroundStyle(Palette.currency)
                    if let unit = tag.unit, !unit.isEmpty {
                        Text(unit).font(.aaCaption).foregroundStyle(Palette.textSecondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(Money.tag(tag)))
            }
        }
    }
}

/// Поле формы: лейбл 13 серым + инпут r10 h50; ошибка — красная рамка и «тряска».
struct FormField<Field: View>: View {
    let label: String
    var error: String?
    var shakeTrigger: Int = 0
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.aaInputLabel)
                .foregroundStyle(Palette.muted)
            field
                .font(.aaInput)
                .foregroundStyle(Palette.textStrong)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(Palette.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                        .strokeBorder(error == nil ? Palette.borderInput : Palette.error, lineWidth: 1)
                )
                .modifier(ShakeEffect(shakes: CGFloat(shakeTrigger)))
                .animation(.default, value: shakeTrigger)
            if let error {
                Text(error)
                    .font(.aaCaption)
                    .foregroundStyle(Palette.error)
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Горизонтальная «тряска» поля при ошибке.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4), y: 0))
    }
}

/// Карточка-плашка (белая r16) для групп контента.
struct CardContainer<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color = Palette.surface
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(fill))
    }
}

/// Undo-снекбар (4 с) снизу экрана.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.aaBodySmall)
                .foregroundStyle(Palette.textProduct)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                Haptics.play(.selection)
                onUndo()
            } label: {
                Text("Отменить").font(.aaButton)
            }
            .buttonStyle(LinkButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .brandGlass(in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .brandShadow(.floating)
        .padding(.horizontal, Spacing.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Баннер «Нет сети».
struct OfflineBanner: View {
    var body: some View {
        Label {
            Text("Нет соединения с интернетом")
        } icon: {
            Image(systemName: "wifi.slash")
        }
        .font(BrandFont.golos(13, .medium, relativeTo: .footnote))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Capsule().fill(Palette.textProduct.opacity(0.88)))
        .accessibilityAddTraits(.isStaticText)
    }
}
