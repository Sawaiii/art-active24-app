import SwiftUI

// Liquid Glass (iOS 26+) для собственных плавающих элементов: липкий бар цены,
// кнопки поверх фото, плавающие фильтры. Системные TabView / NavigationStack / toolbar /
// sheet получают стекло сами. На iOS 17–25 — фолбэк на .ultraThinMaterial.
// `#if compiler(>=6.2)` — чтобы проект собирался и Xcode 16 (без SDK iOS 26).

extension View {
    /// Стеклянная подложка заданной формы.
    @ViewBuilder
    func brandGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(GlassStyle.make(tint: tint, interactive: interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

#if compiler(>=6.2)
@available(iOS 26.0, *)
private enum GlassStyle {
    static func make(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}
#endif

extension View {
    /// Верхний край прокрутки: контент мягко растворяется под статус-баром и плавающими
    /// кнопками навбара. iOS 26 — `scrollEdgeEffectStyle(.soft)`; на iOS 17–25 системный
    /// навбар (без кастомного appearance) сам включает материал, когда под него заезжает контент.
    @ViewBuilder
    func softTopScrollEdge() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Полоса цвета фона под статус-баром и кнопками навбара на экранах с прокруткой под ними
    /// (главная, карточка, площадка): при прокрутке текст уходит под неё, а не просвечивает
    /// под кнопками. В покое под полосой пусто (контент начинается ниже кнопок), поэтому её не видно.
    /// Кнопки навбара рисуются поверх — модификатор вешается на корень экрана внутри стека.
    func topScrollFade(_ color: Color) -> some View {
        overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: color, location: 0),
                    .init(color: color, location: 0.6),
                    .init(color: color.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // 48 pt ниже безопасной зоны (ряд кнопок) + сама зона статус-бара.
            .frame(height: 48)
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Плотная подложка нижней панели (липкий бар цены, «Отправить заявку»):
    /// контент под ней не просвечивает. Тянется под home indicator.
    func stickyBottomBarBackground() -> some View {
        background {
            UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
                        .fill(Palette.page.opacity(0.82))
                )
                .overlay(alignment: .top) {
                    UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
                        .stroke(Palette.stickyBarTop, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: -2)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Группа стеклянных элементов (на iOS 26 — общий `GlassEffectContainer`, стекло «сливается»).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Круглая стеклянная кнопка поверх фото/видео.
struct GlassIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Palette.textProduct)
                .frame(width: size, height: size)
                .brandGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(Text(label))
    }
}
