import Observation
import SwiftUI

@MainActor
@Observable
final class CheckoutViewModel {
    enum Field: Hashable {
        case date, address, phone, name, comment
    }

    var isRange = false
    var dateFrom = DayDate.startOfToday()
    var dateTo = Calendar.current.date(byAdding: .day, value: 1, to: DayDate.startOfToday()) ?? DayDate.startOfToday()
    var delivery: DeliveryMethod = .delivery
    var address = ""
    var name = ""
    var phone = ""
    var comment = ""

    private(set) var errors: [Field: String] = [:]
    private(set) var shake = 0
    private(set) var isSending = false
    private(set) var generalError: String?
    private(set) var createdOrder: Order?

    @ObservationIgnored private let cart: CartStore
    @ObservationIgnored private let orders: OrdersStore
    /// Ключ идемпотентности привязан к телу запроса (см. IdempotencyKey).
    @ObservationIgnored private var idempotency = IdempotencyKey()

    static let addressLimit = 300
    static let commentLimit = 2000

    init(cart: CartStore, orders: OrdersStore, auth: AuthStore) {
        self.cart = cart
        self.orders = orders
        name = auth.user?.name ?? ""
        phone = auth.user.map { PhoneFormatter.display($0.phone) } ?? ""
    }

    var itemsCount: Int { cart.count }
    var total: Int? { cart.quote?.total }
    var hasOnRequest: Bool { cart.quote?.hasOnRequest == true }

    func submit() async {
        guard validate() else {
            shake += 1
            Haptics.play(.error)
            return
        }
        let items = cart.items
        let request = CheckoutRequest(
            items: items,
            eventDate: DayDate.string(from: dateFrom),
            eventDateTo: isRange ? DayDate.string(from: dateTo) : nil,
            delivery: CheckoutDelivery(
                method: delivery,
                address: delivery == .delivery ? address.trimmingCharacters(in: .whitespacesAndNewlines) : nil
            ),
            contactName: name.isEmpty ? nil : String(name.prefix(100)),
            contactPhone: PhoneFormatter.e164(phone),
            comment: comment.isEmpty ? nil : String(comment.prefix(Self.commentLimit))
        )
        isSending = true
        generalError = nil
        defer { isSending = false }
        let key = idempotency.key(for: request)
        do {
            let order = try await orders.checkout(request, idempotencyKey: key)
            idempotency.finish(error: nil)
            cart.clear()
            createdOrder = order
            Haptics.play(.success)
        } catch let error as APIError {
            idempotency.finish(error: error)
            handle(error)
        } catch {
            idempotency.finish(error: error)
            generalError = error.userMessage
            Haptics.play(.error)
        }
    }

    private func handle(_ error: APIError) {
        Haptics.play(.error)
        shake += 1
        if error.statusCode == 409 {
            generalError = String(localized: "Состав корзины изменился — проверьте позиции и отправьте заявку ещё раз.")
            Task { await cart.refreshQuote() }
            return
        }
        let fields = error.fieldErrors
        if !fields.isEmpty {
            for (key, message) in fields {
                switch key {
                case "eventDate", "eventDateTo": errors[.date] = message
                case "delivery.address", "address": errors[.address] = message
                case "contactPhone": errors[.phone] = message
                case "contactName": errors[.name] = message
                case "comment": errors[.comment] = message
                default: generalError = message
                }
            }
            if generalError == nil, errors.isEmpty { generalError = error.userMessage }
            return
        }
        generalError = error.userMessage
    }

    private func validate() -> Bool {
        var result: [Field: String] = [:]
        let today = DayDate.startOfToday()
        if dateFrom < today { result[.date] = String(localized: "Дата не может быть в прошлом") }
        if isRange, dateTo < dateFrom { result[.date] = String(localized: "Дата окончания раньше начала") }
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if delivery == .delivery {
            if trimmedAddress.count < 5 {
                result[.address] = String(localized: "Укажите адрес доставки")
            } else if trimmedAddress.count > Self.addressLimit {
                result[.address] = String(localized: "Адрес слишком длинный")
            }
        }
        if !PhoneFormatter.isValid(phone) { result[.phone] = String(localized: "Введите номер полностью: +7 (999) 999-99-99") }
        if cart.isEmpty { generalError = String(localized: "Корзина пуста") }
        errors = result
        return result.isEmpty && !cart.isEmpty
    }

    func clearError(_ field: Field) { errors[field] = nil }
}

/// Оформление: дата/диапазон, доставка/самовывоз, адрес, имя, телефон, комментарий
/// → POST /v1/orders (Idempotency-Key) → анимация успеха → заказ «В обработке».
struct CheckoutView: View {
    @State private var viewModel: CheckoutViewModel
    @Environment(AppEnvironment.self) private var env
    @Environment(InfoStore.self) private var info
    @FocusState private var focused: CheckoutViewModel.Field?

    init(viewModel: CheckoutViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            dateSection
            deliverySection
            contactsSection
            Section {
                TextField(text: $viewModel.comment, axis: .vertical) { Text("Комментарий: время монтажа, этаж, пожелания") }
                    .lineLimit(3...8)
                    .focused($focused, equals: .comment)
            } header: {
                Text("Комментарий")
            }
            summarySection
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(Text("Оформление"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focused = nil }
            }
        }
        .overlay {
            if let order = viewModel.createdOrder {
                SuccessOverlay(
                    title: String(localized: "Заявка отправлена!"),
                    message: String(localized: "Заказ \(order.number) — «В обработке». Менеджер свяжется с вами.")
                ) {
                    env.router.popToRoot(.cart)
                    env.router.openOrder(id: order.id)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSending)
        .onAppear { Haptics.prepare(.success) }
    }

    private var dateSection: some View {
        Section {
            Toggle(isOn: $viewModel.isRange.animation()) { Text("Несколько дней") }
                .tint(Palette.accent)
            DatePicker(selection: $viewModel.dateFrom, in: DayDate.startOfToday()..., displayedComponents: .date) {
                viewModel.isRange ? Text("Начало") : Text("Дата мероприятия")
            }
            .onChange(of: viewModel.dateFrom) { _, newValue in
                Haptics.play(.selection)
                viewModel.clearError(.date)
                if viewModel.dateTo < newValue { viewModel.dateTo = newValue }
            }
            if viewModel.isRange {
                DatePicker(selection: $viewModel.dateTo, in: viewModel.dateFrom..., displayedComponents: .date) {
                    Text("Окончание")
                }
            }
            if let error = viewModel.errors[.date] {
                FieldError(text: error, shake: viewModel.shake)
            }
        } header: {
            Text("Дата")
        }
    }

    private var deliverySection: some View {
        Section {
            Picker(selection: $viewModel.delivery.animation()) {
                Text("Доставка").tag(DeliveryMethod.delivery)
                Text("Самовывоз").tag(DeliveryMethod.pickup)
            } label: {
                Text("Способ получения")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("checkout.delivery")
            .onChange(of: viewModel.delivery) { _, _ in Haptics.play(.selection) }

            if viewModel.delivery == .delivery {
                TextField(text: $viewModel.address, axis: .vertical) { Text("Город, улица, дом, площадка") }
                    .textContentType(.fullStreetAddress)
                    .lineLimit(1...3)
                    .focused($focused, equals: .address)
                    .onChange(of: viewModel.address) { _, _ in viewModel.clearError(.address) }
                if let error = viewModel.errors[.address] {
                    FieldError(text: error, shake: viewModel.shake)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.info.pickupAddress ?? info.info.address ?? "")
                        .font(.aaBodySmall)
                        .foregroundStyle(Palette.textProduct)
                    if let hours = info.info.pickupHours {
                        Text(hours).font(.aaCaption).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        } header: {
            Text("Получение")
        } footer: {
            if viewModel.delivery == .delivery {
                Text("Стоимость доставки и монтажа рассчитает менеджер.")
            }
        }
    }

    private var contactsSection: some View {
        Section {
            TextField(text: $viewModel.name) { Text("Имя") }
                .textContentType(.name)
                .focused($focused, equals: .name)
            PhoneTextField(text: $viewModel.phone, placeholder: "+7 (999) 999-99-99")
                .frame(minHeight: 32)
                .onChange(of: viewModel.phone) { _, _ in viewModel.clearError(.phone) }
            if let error = viewModel.errors[.phone] {
                FieldError(text: error, shake: viewModel.shake)
            }
        } header: {
            Text("Контакты")
        }
    }

    private var summarySection: some View {
        Section {
            HStack {
                Text("Позиций: \(viewModel.itemsCount)")
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                if let total = viewModel.total {
                    Text(Money.rub(total))
                        .font(.aaCartTotal)
                        .foregroundStyle(Palette.textStrong)
                }
            }
            if viewModel.hasOnRequest {
                Text("Часть позиций — по запросу.").font(.aaCaption).foregroundStyle(Palette.textSecondary)
            }
            if let error = viewModel.generalError {
                FieldError(text: error, shake: viewModel.shake)
            }
            Button {
                focused = nil
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isSending {
                    ProgressView().tint(.white)
                } else {
                    Text("Отправить заявку")
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54, radius: Radius.md, font: .aaSubmit))
            .disabled(viewModel.isSending)
            .accessibilityIdentifier("checkout.submit")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            Text("Онлайн-оплаты нет: менеджер подтвердит наличие и итоговую стоимость.")
        }
    }
}

private struct FieldError: View {
    let text: String
    let shake: Int

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.aaCaption)
            .foregroundStyle(Palette.error)
            .modifier(ShakeEffect(shakes: CGFloat(shake)))
            .animation(.default, value: shake)
            .accessibilityAddTraits(.isStaticText)
    }
}
