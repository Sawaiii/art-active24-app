import Observation
import SwiftUI

// MARK: - Звёзды

/// Оценка 1–5: кнопки-звёзды (44 pt), тактильный отклик на каждый выбор,
/// для VoiceOver — регулируемый элемент «N из 5».
struct StarRatingControl: View {
    @Binding var rating: Int
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = star
                    Haptics.play(.selection)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: size, weight: .medium))
                        .foregroundStyle(star <= rating ? Palette.saleYellow : Palette.textTertiary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Оценка"))
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rating = min(5, rating + 1)
            case .decrement: rating = max(1, rating - 1)
            @unknown default: break
            }
            Haptics.play(.selection)
        }
    }

    private var valueText: Text {
        let value = rating
        return value == 0 ? Text("Нет оценки") : Text("\(value) из 5")
    }
}

/// Звёзды только для показа.
struct StarsView: View {
    let rating: Int
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(star <= rating ? Palette.saleYellow : Palette.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Оценка"))
        .accessibilityValue(valueText)
    }

    private var valueText: Text {
        let value = rating
        return Text("\(value) из 5")
    }
}

// MARK: - Карточка в заказе

/// «Как прошло мероприятие?» — звёзды прямо в карточке; выбор открывает форму отзыва.
/// Отзыв уже есть — показываем его и «Изменить» (7 дней) или «Спасибо за отзыв!».
struct OrderReviewCard: View {
    let review: OrderReview?
    let canReview: Bool
    let onCompose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let review {
                HStack(alignment: .center) {
                    StarsView(rating: review.rating, size: 17)
                    Spacer()
                    if review.canEdit == true && canReview {
                        Button("Изменить") { onCompose(review.rating) }
                            .buttonStyle(LinkButtonStyle())
                            .frame(minHeight: 44)
                    }
                }
                if let text = review.text, !text.isEmpty {
                    Text(text)
                        .font(.aaBodySmall)
                        .foregroundStyle(Palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if review.canEdit == true && canReview, let until = review.editableUntil {
                    Text("Можно изменить до \(DateText.day(until))")
                        .font(.aaCaption)
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    Label("Спасибо за отзыв!", systemImage: "heart.fill")
                        .font(.aaCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                Text("Как прошло мероприятие?")
                    .font(BrandFont.golos(17, .semibold, relativeTo: .headline))
                    .foregroundStyle(Palette.textProduct)
                Text("Оцените работу команды — это займёт минуту")
                    .font(.aaBodySmall)
                    .foregroundStyle(Palette.textSecondary)
                StarRatingControl(rating: Binding(get: { 0 }, set: { onCompose($0) }), size: 30)
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("orderDetail.review")
    }
}

// MARK: - Форма отзыва

@MainActor
@Observable
final class ReviewFormViewModel {
    static let textLimit = 2000

    var rating: Int
    var text: String
    private(set) var isSending = false
    private(set) var errorMessage: String?
    private(set) var isDone = false

    @ObservationIgnored private let orderId: Int
    @ObservationIgnored private let orders: OrdersStore

    init(orderId: Int, orders: OrdersStore, rating: Int, text: String?) {
        self.orderId = orderId
        self.orders = orders
        self.rating = min(max(rating, 0), 5)
        self.text = text ?? ""
    }

    func submit() async {
        guard (1...5).contains(rating) else {
            errorMessage = String(localized: "Поставьте оценку от 1 до 5")
            Haptics.play(.error)
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await orders.submitReview(
                orderId: orderId,
                ReviewInput(rating: rating, text: trimmed.isEmpty ? nil : String(trimmed.prefix(Self.textLimit)))
            )
            isDone = true
            Haptics.play(.success)
        } catch {
            errorMessage = (error as? APIError)?.fieldErrors.values.first ?? error.userMessage
            Haptics.play(.error)
        }
    }
}

struct ReviewFormSheet: View {
    @State private var viewModel: ReviewFormViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFocused: Bool

    init(viewModel: ReviewFormViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isDone {
                    thanks
                } else {
                    form
                }
            }
            .navigationTitle(Text("Отзыв о мероприятии"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(viewModel.isSending)
        .onAppear { Haptics.prepare(.success) }
    }

    private var form: some View {
        Form {
            Section {
                StarRatingControl(rating: $viewModel.rating, size: 34)
                    .frame(maxWidth: .infinity)
            } header: {
                Text("Ваша оценка")
            }
            Section {
                TextField(text: $viewModel.text, axis: .vertical) { Text("Что понравилось, что можно улучшить?") }
                    .lineLimit(4...10)
                    .focused($isTextFocused)
                    .onChange(of: viewModel.text) { _, newValue in
                        if newValue.count > ReviewFormViewModel.textLimit {
                            viewModel.text = String(newValue.prefix(ReviewFormViewModel.textLimit))
                        }
                    }
            } header: {
                Text("Комментарий")
            } footer: {
                Text(verbatim: "\(viewModel.text.count) / \(ReviewFormViewModel.textLimit)")
            }
            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.aaCaption)
                        .foregroundStyle(Palette.error)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                isTextFocused = false
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isSending { ProgressView().tint(.white) } else { Text("Отправить отзыв") }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54, radius: Radius.md, font: .aaSubmit))
            .disabled(viewModel.isSending || viewModel.rating == 0)
            .accessibilityIdentifier("review.submit")
            .padding(.horizontal, Spacing.gutterProduct)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .stickyBottomBarBackground()
        }
    }

    private var thanks: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.success)
                .accessibilityHidden(true)
            Text("Спасибо за отзыв!")
                .font(.aaCartTitle)
                .foregroundStyle(Palette.textProduct)
            Text("Мы передали его команде мероприятия.")
                .font(.aaBodySmall)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
            Button("Готово") { dismiss() }
                .buttonStyle(PrimaryButtonStyle(height: 48, radius: Radius.md))
                .frame(maxWidth: 240)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
