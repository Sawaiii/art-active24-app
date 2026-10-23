import Observation
import SwiftUI

/// Что заказываем заявкой (без корзины).
struct RequestSubject: Identifiable, Hashable {
    let kind: RequestKind
    let title: String
    var productId: Int?
    var complectId: Int?
    var venueId: Int?
    /// Для площадок: типы событий для выбора и обязательная дата.
    var eventTypes: [String] = []
    var requiresDate = false
    var minHoursNote: String?
    /// Готовый комментарий для менеджера (кейс «Хочу так же», акция) — пользователь может изменить.
    var comment: String?

    var id: String { "\(kind.rawValue)-\(productId ?? 0)-\(complectId ?? 0)-\(venueId ?? 0)" }
}

@MainActor
@Observable
final class RequestFormViewModel {
    let subject: RequestSubject
    var hasDate: Bool
    var date = DayDate.startOfToday()
    var eventType = ""
    var guests = ""
    var comment = ""
    private(set) var isSending = false
    private(set) var errorMessage: String?
    private(set) var createdOrder: Order?
    private(set) var shakeTrigger = 0

    @ObservationIgnored private let orders: OrdersStore
    /// Ключ привязан к телу запроса: повтор после сбоя сети не создаст дубль.
    @ObservationIgnored private var idempotency = IdempotencyKey()

    init(subject: RequestSubject, orders: OrdersStore) {
        self.subject = subject
        self.orders = orders
        hasDate = subject.requiresDate
        comment = subject.comment ?? ""
    }

    var guestsValue: Int? {
        let digits = guests.filter(\.isNumber)
        guard let value = Int(digits), value >= 1 else { return nil }
        return min(value, 100_000)
    }

    func submit() async {
        errorMessage = nil
        if subject.requiresDate, !hasDate {
            fail(String(localized: "Укажите дату мероприятия"))
            return
        }
        if !guests.isEmpty, guestsValue == nil {
            fail(String(localized: "Количество гостей — число от 1"))
            return
        }
        isSending = true
        defer { isSending = false }
        let request = RequestCreate(
            kind: subject.kind,
            productId: subject.productId,
            complectId: subject.complectId,
            venueId: subject.venueId,
            eventDate: hasDate ? DayDate.string(from: date) : nil,
            eventType: eventType.isEmpty ? nil : String(eventType.prefix(100)),
            guests: guestsValue,
            comment: comment.isEmpty ? nil : String(comment.prefix(2000))
        )
        let key = idempotency.key(for: request)
        do {
            createdOrder = try await orders.createRequest(request, idempotencyKey: key)
            idempotency.finish(error: nil)
            Haptics.play(.success)
        } catch {
            idempotency.finish(error: error)
            fail(error.userMessage)
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        shakeTrigger += 1
        Haptics.play(.error)
    }
}

/// Форма заявки (персонал, программа, «Заказать» у комплекта, «Заявка на расчёт» площадки).
struct RequestFormSheet: View {
    @State private var viewModel: RequestFormViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @Environment(Router.self) private var router

    init(viewModel: RequestFormViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(viewModel.subject.title)
                        .font(BrandFont.golos(16, .semibold))
                        .foregroundStyle(Palette.textProduct)
                    if let note = viewModel.subject.minHoursNote {
                        Text(note).font(.aaCaption).foregroundStyle(Palette.textSecondary)
                    }
                }
                Section {
                    if !viewModel.subject.requiresDate {
                        Toggle(isOn: $viewModel.hasDate.animation()) { Text("Знаю дату мероприятия") }
                            .tint(Palette.accent)
                    }
                    if viewModel.hasDate {
                        DatePicker(selection: $viewModel.date, in: DayDate.startOfToday()..., displayedComponents: .date) {
                            Text("Дата")
                        }
                    }
                    if !viewModel.subject.eventTypes.isEmpty {
                        Picker(selection: $viewModel.eventType) {
                            Text("Не выбрано").tag("")
                            ForEach(viewModel.subject.eventTypes, id: \.self) { type in
                                Text(type).tag(type)
                            }
                        } label: {
                            Text("Тип мероприятия")
                        }
                    }
                    TextField(text: $viewModel.guests) { Text("Количество гостей") }
                        .keyboardType(.numberPad)
                } header: {
                    Text("Мероприятие")
                }
                Section {
                    TextField(text: $viewModel.comment, axis: .vertical) { Text("Комментарий для менеджера") }
                        .lineLimit(3...6)
                } footer: {
                    if let phone = auth.user?.phone {
                        Text("Менеджер свяжется с вами по номеру \(PhoneFormatter.display(phone)).")
                    }
                }
                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.error)
                            .modifier(ShakeEffect(shakes: CGFloat(viewModel.shakeTrigger)))
                            .animation(.default, value: viewModel.shakeTrigger)
                    }
                }
                Section {
                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        if viewModel.isSending { ProgressView().tint(.white) } else { Text("Отправить заявку") }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 52, radius: Radius.md, font: .aaSubmit))
                    .disabled(viewModel.isSending)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(Text("Заявка"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .overlay {
                if let order = viewModel.createdOrder {
                    SuccessOverlay(
                        title: String(localized: "Заявка отправлена!"),
                        message: String(localized: "Номер \(order.number). Менеджер свяжется с вами в ближайшее время.")
                    ) {
                        dismiss()
                        router.openOrder(id: order.id)
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSending)
    }
}

/// Модалка успеха: фиолетовые круги, галочка, scale .85→1, автозакрытие 2.5 с.
struct SuccessOverlay: View {
    let title: String
    let message: String
    let onFinish: () -> Void

    @State private var appeared = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinish()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(Palette.accentTint10).frame(width: 112, height: 112)
                    Circle().fill(Palette.accentTint15).frame(width: 84, height: 84)
                        .scaleEffect(appeared ? 1 : 0.6)
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Palette.accent)
                        .symbolEffect(.bounce, value: appeared)
                }
                ConfettiBurst(isActive: appeared && !reduceMotion)
                    .frame(height: 0)
                Text(title)
                    .font(BrandFont.golos(20, .bold, relativeTo: .title3))
                    .foregroundStyle(Palette.textProduct)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(BrandFont.golos(14, relativeTo: .subheadline))
                    .foregroundStyle(Palette.muted2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.top, 40)
            .padding(.horizontal, 36)
            .padding(.bottom, 36)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.surface))
            .brandShadow(.modal)
            .padding(.horizontal, 32)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
        .onTapGesture { finish() }
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.6)) {
                appeared = true
            }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            finish()
        }
    }
}

/// Лёгкое конфетти из точек бренда (без сторонних зависимостей).
struct ConfettiBurst: View {
    let isActive: Bool
    private let colors: [Color] = [Palette.accent, Palette.saleYellow, Palette.logoViolet, Palette.success]

    var body: some View {
        ZStack {
            ForEach(0..<18, id: \.self) { index in
                let angle = Double(index) / 18 * 2 * .pi
                let distance: CGFloat = isActive ? CGFloat(90 + (index % 4) * 18) : 0
                Circle()
                    .fill(colors[index % colors.count])
                    .frame(width: 7, height: 7)
                    .offset(x: cos(angle) * distance, y: sin(angle) * distance - 70)
                    .opacity(isActive ? 0 : 1)
                    .animation(.easeOut(duration: 0.9).delay(Double(index % 3) * 0.04), value: isActive)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
