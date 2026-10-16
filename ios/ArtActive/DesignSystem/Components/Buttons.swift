import SwiftUI

/// Основная фиолетовая кнопка: «В корзину», «Оставить заявку», «Войти».
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    var radius: CGFloat = Radius.button
    var font: Font = .aaButtonLarge
    var shadow = true

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, style: self)
    }

    private struct PrimaryButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let style: PrimaryButtonStyle
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .font(style.font)
                .foregroundStyle(Palette.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: style.height)
                .background(
                    RoundedRectangle(cornerRadius: style.radius, style: .continuous)
                        .fill(isEnabled ? (configuration.isPressed ? Palette.accentPressed : Palette.accent) : Palette.disabled)
                )
                .modifier(OptionalShadow(enabled: style.shadow && isEnabled))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .animation(Motion.fast(reduceMotion), value: configuration.isPressed)
                .contentShape(Rectangle())
        }
    }

    private struct OptionalShadow: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled { content.brandShadow(.primaryButton) } else { content }
        }
    }
}

/// Белая кнопка (на сером фоне): «Смотреть каталог».
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 48
    var fill: Color = Palette.surface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.aaButtonLarge)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .fill(configuration.isPressed ? Palette.surfaceMuted2 : fill)
            )
            .contentShape(Rectangle())
    }
}

/// Контурная пилюля: «Показать ещё».
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BrandFont.golos(15, .medium))
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 28)
            .frame(minHeight: 48)
            .background(Capsule().fill(configuration.isPressed ? Palette.accentTint08 : .clear))
            .overlay(Capsule().strokeBorder(Palette.accent, lineWidth: 2))
            .contentShape(Capsule())
    }
}

/// Текстовая кнопка-ссылка в цвет акцента: «Показать все 5».
struct LinkButtonStyle: ButtonStyle {
    var font: Font = .aaChip
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(Palette.accent.opacity(configuration.isPressed ? 0.6 : 1))
            .contentShape(Rectangle())
    }
}

/// Для карточек и плиток: лёгкое «вдавливание».
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, scale: scale)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
                .opacity(configuration.isPressed ? 0.92 : 1)
                .animation(Motion.fast(reduceMotion), value: configuration.isPressed)
        }
    }
}

/// Круглая иконка-кнопка 36pt (закрыть шит, избранное поверх фото).
struct CircleIconButton: View {
    let systemName: String
    let label: String
    var size: CGFloat = 36
    var foreground: Color = Palette.textTertiary
    var background: Color = Palette.surfaceMuted
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }
}

/// Сердечко «В избранное» с пульсом и хаптиком.
struct FavoriteButton: View {
    let isOn: Bool
    var size: CGFloat = 34
    var onDark = false
    let action: () -> Void

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Haptics.play(.favorite)
            action()
            guard !reduceMotion else { return }
            pulse = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { pulse = false }
        } label: {
            Image(systemName: isOn ? "heart.fill" : "heart")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(isOn ? Palette.accent : (onDark ? .white : Palette.textSecondary))
                .scaleEffect(pulse ? 1.35 : 1)
                .frame(width: size, height: size)
                .background(Circle().fill(onDark ? Palette.glassDark : Palette.surface.opacity(0.92)))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? Text("Убрать из избранного") : Text("В избранное"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
