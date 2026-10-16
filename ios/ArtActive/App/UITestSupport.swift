import SwiftUI

/// Режим UI-тестов (скриншоты в CI). Работает только в Debug и только с launch-аргументом
/// `-UITests YES`; в Release все значения — «выключено».
///
/// - `UITEST_APPEARANCE=dark|light` (launch environment) — принудительная тема;
/// - `UITEST_DEEPLINK=artactive24://product/7138` — открыть экран после старта;
/// - анимации UIKit отключаются, системный запрос push-разрешения не показывается.
enum UITestSupport {
    #if DEBUG
    static let isActive: Bool = ProcessInfo.processInfo.arguments.contains("-UITests")

    static var colorScheme: ColorScheme? {
        guard isActive else { return nil }
        switch ProcessInfo.processInfo.environment["UITEST_APPEARANCE"] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    static var deepLink: URL? {
        guard isActive, let raw = ProcessInfo.processInfo.environment["UITEST_DEEPLINK"] else { return nil }
        return URL(string: raw)
    }
    #else
    static let isActive = false
    static let colorScheme: ColorScheme? = nil
    static let deepLink: URL? = nil
    #endif
}
