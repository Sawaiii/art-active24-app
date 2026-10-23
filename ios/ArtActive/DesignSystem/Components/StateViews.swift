import SwiftUI

/// Состояние экрана: загрузка / контент / пусто / ошибка.
enum ViewState<Content> {
    case loading
    case content(Content)
    case empty
    case error(String)

    var content: Content? {
        if case let .content(value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Shimmer / skeleton

/// Мерцание скелетона; при Reduce Motion — статичный.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.55), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Блок скелетона заданной формы.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = Radius.sm

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Palette.bgTertiary.opacity(0.7))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

/// Скелетон сетки карточек листинга.
struct ProductGridSkeleton: View {
    var count = 6
    var body: some View {
        LazyVGrid(columns: ProductGrid.columns, spacing: 20) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.cardInner) {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(Palette.bgTertiary.opacity(0.7))
                        .aspectRatio(1, contentMode: .fit)
                    SkeletonBlock(height: 14)
                    SkeletonBlock(width: 90, height: 16)
                }
            }
        }
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Загрузка"))
    }
}

/// Скелетон списка строк.
struct ListSkeleton: View {
    var rows = 6
    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: 12) {
                    SkeletonBlock(width: 56, height: 56, radius: Radius.md)
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: 14)
                        SkeletonBlock(width: 120, height: 12)
                    }
                }
            }
        }
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Загрузка"))
    }
}

// MARK: - Error / empty

struct ErrorStateView: View {
    let message: String
    var retry: (() async -> Void)?

    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Palette.accent)
                .frame(width: 84, height: 84)
                .background(Circle().fill(Palette.accentTint10))
            Text("Не получилось загрузить")
                .font(.aaCartTitle)
                .foregroundStyle(Palette.textProduct)
            Text(message)
                .font(.aaBodySmall)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button {
                    Task {
                        isRetrying = true
                        await retry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying { ProgressView().tint(.white) } else { Text("Повторить") }
                }
                .buttonStyle(PrimaryButtonStyle(height: 48))
                .frame(maxWidth: 220)
                .disabled(isRetrying)
                .accessibilityLabel(Text("Повторить"))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .onAppear { Haptics.play(.error) }
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Palette.accentTint06).frame(width: 120, height: 120)
                Circle().fill(Palette.accentTint10).frame(width: 84, height: 84)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(Palette.accent)
            }
            .accessibilityHidden(true)
            Text(title)
                .font(.aaCartTitle)
                .foregroundStyle(Palette.textProduct)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.aaBodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle(height: 48))
                    .frame(maxWidth: 260)
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Подвал списка: «грузим ещё» / ошибка догрузки.
struct LoadMoreFooter: View {
    let isLoading: Bool
    var error: String?
    var retry: (() -> Void)?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().tint(Palette.accent)
                    .accessibilityLabel(Text("Загрузка"))
            } else if let error {
                VStack(spacing: 8) {
                    Text(error).font(.aaCaption).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
                    if let retry {
                        Button("Повторить", action: retry).buttonStyle(OutlineButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 8)
    }
}

/// Сообщение-плашка (info note): фиолетовый тинт r8.
struct InfoNote: View {
    let title: String
    var message: String?
    var systemImage = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(BrandFont.golos(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textStrong)
                if let message {
                    Text(message)
                        .font(.aaBodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.accentTint06))
        .accessibilityElement(children: .combine)
    }
}
