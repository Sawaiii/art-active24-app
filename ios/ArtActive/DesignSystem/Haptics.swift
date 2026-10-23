import UIKit

/// Единый словарь тактильных откликов (docs/UX.md). Экраны вызывают событие,
/// а не API платформы. Системная настройка «Системные тактильные сигналы» уважается
/// генераторами UIKit автоматически.
@MainActor
enum Haptics {
    enum Event {
        /// Таб, чип, сегмент, выбор комплекта.
        case selection
        /// Шаг степпера/пикера.
        case step
        /// Упёрлись в мин/макс степпера.
        case limit
        /// Добавлено в корзину.
        case addedToCart
        /// В избранное / убрали.
        case favorite
        /// Свайп-удаление перешёл порог.
        case swipeThreshold
        /// Pull-to-refresh перешёл порог.
        case refresh
        /// Заказ оформлен.
        case success
        /// Ошибка (валидация, сеть).
        case error
        /// Код из SMS введён полностью.
        case codeComplete
        /// Long-press на карточке.
        case longPress
        /// Заставка: штрих буквы «А» лёг на место.
        case splashStroke
        /// Заставка: буква собрана — плотная «посадка» с отдачей.
        case splashLand
    }

    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notificationGenerator = UINotificationFeedbackGenerator()
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)

    /// Прогреть движок перед жестом (степпер, свайп, отправка формы) — отклик без задержки.
    static func prepare(_ event: Event) {
        switch event {
        case .selection, .step: selectionGenerator.prepare()
        case .addedToCart, .swipeThreshold: mediumImpact.prepare()
        case .success, .codeComplete, .error: notificationGenerator.prepare()
        case .splashStroke: softImpact.prepare()
        case .splashLand: rigidImpact.prepare()
        default: break
        }
    }

    static func play(_ event: Event) {
        switch event {
        case .selection, .step:
            selectionGenerator.selectionChanged()
            selectionGenerator.prepare()
        case .limit:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
        case .addedToCart, .swipeThreshold:
            mediumImpact.impactOccurred()
        case .favorite, .refresh:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success, .codeComplete:
            notificationGenerator.notificationOccurred(.success)
        case .error:
            notificationGenerator.notificationOccurred(.error)
        case .longPress:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .splashStroke:
            softImpact.impactOccurred(intensity: 0.7)
            softImpact.prepare()
        case .splashLand:
            rigidImpact.impactOccurred(intensity: 1.0)
        }
    }
}
