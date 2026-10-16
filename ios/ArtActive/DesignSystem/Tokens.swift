import SwiftUI
import UIKit

extension Color {
    /// `Color(hex: 0x705ABF)`
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Цвет из строки сервера: «#705ABF», «705ABF», «#FFF». Мусор → nil.
    init?(hexString: String?) {
        guard var raw = hexString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") { raw.removeFirst() }
        if raw.count == 3 { raw = raw.map { "\($0)\($0)" }.joined() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    /// Динамический цвет: светлая тема — айдентика сайта, тёмная — выведенная из неё палитра.
    init(light: UInt32, dark: UInt32, lightOpacity: CGFloat = 1, darkOpacity: CGFloat = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkOpacity)
                : UIColor(hex: light, alpha: lightOpacity)
        })
    }
}

/// Палитра сайта 1-в-1 (research/brand/tokens.json) + тёмная тема, выведенная из айдентики:
/// фон — системный чёрный/#1C1C1E, акцент чуть светлее для контраста ≥ 4.5:1.
enum Palette {
    // Бренд
    static let accent = Color(light: 0x705ABF, dark: 0x9A87E6)
    static let accentHover = Color(light: 0x6350AD, dark: 0x8D79DD)
    static let accentPressed = Color(light: 0x5F49AD, dark: 0x8470D6)
    static let accentTint05 = Color(light: 0x705ABF, dark: 0x9A87E6, lightOpacity: 0.05, darkOpacity: 0.10)
    static let accentTint06 = Color(light: 0x705ABF, dark: 0x9A87E6, lightOpacity: 0.06, darkOpacity: 0.12)
    static let accentTint08 = Color(light: 0x705ABF, dark: 0x9A87E6, lightOpacity: 0.08, darkOpacity: 0.14)
    static let accentTint10 = Color(light: 0x705ABF, dark: 0x9A87E6, lightOpacity: 0.10, darkOpacity: 0.18)
    static let accentTint15 = Color(light: 0x705ABF, dark: 0x9A87E6, lightOpacity: 0.15, darkOpacity: 0.24)
    static let accentShadow = Color(light: 0x705ABF, dark: 0x000000, lightOpacity: 0.25, darkOpacity: 0.4)
    static let accentSoft = Color(light: 0xE3DEF3, dark: 0x2E2748)
    static let accentSoftAlt = Color(light: 0xF0EBFB, dark: 0x251F3B)
    static let saleYellow = Color(hex: 0xF2B807)
    static let dayBadge = Color(hex: 0xFACC15)
    /// Текст на жёлтом бейдже — тёмный в обеих темах.
    static let onYellow = Color(hex: 0x1A1A1A)
    static let logoViolet = Color(hex: 0x6D0FF2)

    // Текст
    static let text = Color(light: 0x3B3B3B, dark: 0xE5E5EA)
    static let textProduct = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let textStrong = Color(light: 0x222222, dark: 0xF2F2F7)
    static let ink = Color(light: 0x1A1A1A, dark: 0xF5F5F7)
    static let textSecondary = Color(light: 0x6E6E73, dark: 0xA1A1A6)
    static let textSecondaryDarker = Color(light: 0x58585D, dark: 0xB4B4B9)
    static let textTertiary = Color(light: 0x86868B, dark: 0x8E8E93)
    static let muted = Color(light: 0x888888, dark: 0x8E8E93)
    static let muted2 = Color(light: 0x999999, dark: 0x8E8E93)
    static let disabled = Color(light: 0xAFAFAF, dark: 0x636366)
    static let breadcrumb = Color(light: 0xB8B8B8, dark: 0x6E6E73)
    static let currency = Color(light: 0xB8B8B8, dark: 0x8E8E93)
    static let placeholder = Color(light: 0xBBBBBB, dark: 0x636366)
    static let variantPrice = Color(light: 0x676767, dark: 0xA1A1A6)
    static let onAccent = Color.white

    // Фоны
    static let page = Color(light: 0xFFFFFF, dark: 0x000000)
    static let catalogPage = Color(light: 0xF5F5F7, dark: 0x000000)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surfaceMuted = Color(light: 0xF5F5F7, dark: 0x2C2C2E)
    static let surfaceMuted2 = Color(light: 0xF2F2F2, dark: 0x3A3A3C)
    static let imagePlaceholder = Color(light: 0xF1F1F5, dark: 0x2C2C2E)
    static let chipArticle = Color(light: 0xF2F2F5, dark: 0x2C2C2E)
    static let bgTertiary = Color(light: 0xE8E8ED, dark: 0x3A3A3C)
    static let segmented = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.04, darkOpacity: 0.08)
    static let overlay = Color.black.opacity(0.35)
    static let overlayDark = Color.black.opacity(0.60)
    static let glassDark = Color(hex: 0x141416, opacity: 0.55)

    // Рамки
    static let hairline = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.06, darkOpacity: 0.08)
    static let border = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.10, darkOpacity: 0.14)
    static let borderStrong = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.15, darkOpacity: 0.22)
    static let borderInput = Color(light: 0xE0E0E0, dark: 0x3A3A3C)
    static let divider = Color(light: 0xEEEEEE, dark: 0x2C2C2E)
    static let stickyBarTop = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.08, darkOpacity: 0.10)

    // Статусы
    static let success = Color(light: 0x34C759, dark: 0x30D158)
    static let successBg = Color(light: 0x34C759, dark: 0x30D158, lightOpacity: 0.08, darkOpacity: 0.16)
    static let warning = Color(light: 0xFF9500, dark: 0xFF9F0A)
    static let danger = Color(light: 0xFF3B30, dark: 0xFF453A)
    static let error = Color(light: 0xF25757, dark: 0xFF6961)

    /// Градиент формы заявки (как на сайте).
    static let leadGradient = LinearGradient(
        colors: [Color(hex: 0x705ABF), Color(hex: 0x9A7EDD), Color(hex: 0xC9A6F0), Color(hex: 0xF2B807), Color(hex: 0xC9A6F0), Color(hex: 0x9A7EDD)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum Radius {
    static let xs: CGFloat = 5
    static let article: CGFloat = 6
    static let sm: CGFloat = 8
    static let input: CGFloat = 10
    static let md: CGFloat = 12
    static let button: CGFloat = 14
    static let card: CGFloat = 16
    static let lg: CGFloat = 20
    static let sheet: CGFloat = 24
    static let catalogLayer: CGFloat = 40
}

enum Spacing {
    static let gutter: CGFloat = 15
    static let gutterProduct: CGFloat = 16
    static let gridGap: CGFloat = 15
    static let cardInner: CGFloat = 10
    static let section: CGFloat = 16
    static let sectionLarge: CGFloat = 32
    static let tabBarHeight: CGFloat = 50
}

/// Тени токенов как модификаторы.
enum ShadowStyle {
    case floating, primaryButton, segmentActive, toggleActive, dropdown, modal, sheet, card
}

extension View {
    @ViewBuilder
    func brandShadow(_ style: ShadowStyle) -> some View {
        switch style {
        case .floating:
            shadow(color: .black.opacity(0.05), radius: 8, y: 4).shadow(color: .black.opacity(0.12), radius: 20, y: 4)
        case .primaryButton:
            shadow(color: Palette.accentShadow, radius: 8, y: 4)
        case .segmentActive:
            shadow(color: .black.opacity(0.08), radius: 1.5, y: 1).shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        case .toggleActive:
            shadow(color: Palette.accentTint15, radius: 2, y: 1)
        case .dropdown:
            shadow(color: .black.opacity(0.08), radius: 14, y: 12).shadow(color: .black.opacity(0.04), radius: 3, y: 2)
        case .modal:
            shadow(color: .black.opacity(0.12), radius: 24, y: 16)
        case .sheet:
            shadow(color: .black.opacity(0.12), radius: 30, y: 20)
        case .card:
            shadow(color: .black.opacity(0.06), radius: 10, y: 4).shadow(color: .black.opacity(0.04), radius: 3, y: 2)
        }
    }
}

/// Анимации токенов с учётом Reduce Motion.
enum Motion {
    static func fast(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }
    static func slow(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .timingCurve(0.25, 0.1, 0.25, 1, duration: 0.4) }
    static func pop(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6) }
    static func snappy(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .snappy(duration: 0.25) }
}
