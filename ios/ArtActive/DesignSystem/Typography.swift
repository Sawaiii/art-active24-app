import SwiftUI
import UIKit

/// Шрифты сайта: Golos Text — общие экраны, Inter — карточка товара.
/// Все размеры масштабируются Dynamic Type через `relativeTo:`.
enum BrandFont {
    enum Family {
        case golos, inter

        func name(_ weight: Font.Weight) -> String {
            let suffix: String
            switch weight {
            case .bold, .heavy, .black: suffix = "Bold"
            case .semibold: suffix = "SemiBold"
            case .medium: suffix = "Medium"
            default: suffix = "Regular"
            }
            switch self {
            case .golos: return "GolosText-\(suffix)"
            case .inter: return "Inter-\(suffix)"
            }
        }
    }

    static func golos(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(Family.golos.name(weight), size: size, relativeTo: style)
    }

    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(Family.inter.name(weight), size: size, relativeTo: style)
    }

    static func uiFont(_ family: Family, _ weight: Font.Weight, size: CGFloat, style: UIFont.TextStyle) -> UIFont {
        let base = UIFont(name: family.name(weight), size: size) ?? .systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

/// Шкала из tokens.json.
extension Font {
    // Golos (общие экраны)
    static let aaHero = BrandFont.golos(40, .semibold, relativeTo: .largeTitle)
    static let aaPageTitle = BrandFont.golos(22, .semibold, relativeTo: .title2)
    static let aaCartTitle = BrandFont.golos(20, .bold, relativeTo: .title3)
    static let aaSectionTitle = BrandFont.golos(24, .semibold, relativeTo: .title2)
    static let aaBlockTitle = BrandFont.golos(15, .semibold, relativeTo: .headline)
    static let aaBody = BrandFont.golos(16, .regular, relativeTo: .body)
    static let aaBodySmall = BrandFont.golos(14, .regular, relativeTo: .subheadline)
    static let aaCardTitle = BrandFont.golos(15, .regular, relativeTo: .subheadline)
    static let aaCardPriceFrom = BrandFont.golos(12, .regular, relativeTo: .caption)
    static let aaCardPrice = BrandFont.golos(18, .medium, relativeTo: .headline)
    static let aaChip = BrandFont.golos(14, .medium, relativeTo: .subheadline)
    static let aaButton = BrandFont.golos(14, .semibold, relativeTo: .subheadline)
    static let aaButtonLarge = BrandFont.golos(15, .semibold, relativeTo: .body)
    static let aaSubmit = BrandFont.golos(16, .semibold, relativeTo: .body)
    static let aaInput = BrandFont.golos(15, .regular, relativeTo: .body)
    static let aaInputLabel = BrandFont.golos(13, .regular, relativeTo: .footnote)
    static let aaBreadcrumb = BrandFont.golos(14, .regular, relativeTo: .footnote)
    static let aaCaption = BrandFont.golos(12, .regular, relativeTo: .caption)
    static let aaTabBar = BrandFont.golos(11, .semibold, relativeTo: .caption2)
    static let aaCounter = BrandFont.golos(10, .semibold, relativeTo: .caption2)
    static let aaCartItemName = BrandFont.golos(13, .medium, relativeTo: .footnote)
    static let aaCartItemPrice = BrandFont.golos(14, .bold, relativeTo: .subheadline)
    static let aaCartTotal = BrandFont.golos(22, .bold, relativeTo: .title2)

    // Inter (карточка товара)
    static let pTitle = BrandFont.inter(17, .semibold, relativeTo: .headline)
    static let pBody = BrandFont.inter(15, .regular, relativeTo: .body)
    static let pSection = BrandFont.inter(24, .bold, relativeTo: .title2)
    static let pH3 = BrandFont.inter(18, .bold, relativeTo: .title3)
    static let pStepLabel = BrandFont.inter(13, .regular, relativeTo: .footnote)
    static let pVariantTitle = BrandFont.inter(12, .semibold, relativeTo: .caption)
    static let pVariantPrice = BrandFont.inter(12, .medium, relativeTo: .caption)
    static let pPriceAmount = BrandFont.inter(18, .bold, relativeTo: .headline)
    static let pPriceLabel = BrandFont.inter(11, .medium, relativeTo: .caption2)
    static let pSegment = BrandFont.inter(12, .regular, relativeTo: .caption)
    static let pSegmentActive = BrandFont.inter(12, .semibold, relativeTo: .caption)
    static let pBadge = BrandFont.inter(12, .medium, relativeTo: .caption)
    static let pBadgeBold = BrandFont.inter(12, .bold, relativeTo: .caption)
    static let pCartButton = BrandFont.inter(14, .semibold, relativeTo: .subheadline)
}

/// Внешний вид UIKit-элементов: только шрифты сайта. Фон, стекло (iOS 26), тёмная тема
/// и поведение large title остаются системными — айдентика поверх HIG.
@MainActor
enum Appearance {
    static func configure() {
        let titleFont = BrandFont.uiFont(.golos, .semibold, size: 17, style: .headline)
        let largeTitleFont = BrandFont.uiFont(.golos, .semibold, size: 30, style: .largeTitle)
        let bar = UINavigationBar.appearance()
        bar.titleTextAttributes = [.font: titleFont]
        bar.largeTitleTextAttributes = [.font: largeTitleFont]

        let tabBar = UITabBarAppearance()
        tabBar.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: BrandFont.uiFont(.golos, .medium, size: 13, style: .subheadline)], for: .normal
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.font: BrandFont.uiFont(.golos, .semibold, size: 13, style: .subheadline)], for: .selected
        )
    }
}
