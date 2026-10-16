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
