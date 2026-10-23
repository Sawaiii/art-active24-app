import Observation
import SwiftUI
import UIKit

// MARK: - Форма претензии

@MainActor
@Observable
final class ClaimFormViewModel {
    enum Field: Hashable {
        case category, description, contact
    }

    static let descriptionMin = 10
    static let descriptionLimit = 2000

    var category: ClaimCategory?
    var text = ""
    var contact: ContactPreference = .call
    private(set) var errors: [Field: String] = [:]
    private(set) var generalError: String?
    private(set) var isSending = false
    private(set) var created: OrderClaim?
    private(set) var shake = 0

    @ObservationIgnored private let orderId: Int
    @ObservationIgnored private let orders: OrdersStore

    init(orderId: Int, orders: OrdersStore) {
        self.orderId = orderId
        self.orders = orders
    }

    var trimmedCount: Int { text.trimmingCharacters(in: .whitespacesAndNewlines).count }

    func clearError(_ field: Field) { errors[field] = nil }

    func submit() async {
        var found: [Field: String] = [:]
        if category == nil { found[.category] = String(localized: "Выберите, что случилось") }
        if trimmedCount < Self.descriptionMin {
            found[.description] = String(localized: "Опишите ситуацию подробнее — хотя бы пару предложений")
        }
        errors = found
        guard found.isEmpty, let category else {
            shake += 1
            Haptics.play(.error)
            return
        }
        isSending = true
        generalError = nil
        defer { isSending = false }
        let input = ClaimInput(
            category: category,
            description: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.descriptionLimit)),
            contactPreference: contact,
            photos: nil
        )
        do {
            created = try await orders.submitClaim(orderId: orderId, input)
            Haptics.play(.success)
        } catch let error as APIError {
            Haptics.play(.error)
            shake += 1
            for (key, message) in error.fieldErrors {
                switch key {
                case "category": errors[.category] = message
                case "description": errors[.description] = message
                case "contactPreference": errors[.contact] = message
                default: generalError = message
                }
            }
            if error.fieldErrors.isEmpty { generalError = error.userMessage }
        } catch {
            Haptics.play(.error)
            generalError = error.userMessage
        }
    }
}

/// «Что-то пошло не так?»: категория, описание, как связаться → претензия уходит менеджеру.
struct ClaimFormSheet: View {
    @State private var viewModel: ClaimFormViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFocused: Bool

    init(viewModel: ClaimFormViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.created != nil {
                    sent
                } else {
                    form
                }
            }
            .navigationTitle(Text("Что-то пошло не так?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { isTextFocused = false }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSending || (!viewModel.text.isEmpty && viewModel.created == nil))
        .onAppear { Haptics.prepare(.success) }
    }

    private var form: some View {
        Form {
            Section {
                Text("Нам жаль, что так вышло. Расскажите, что случилось, — менеджер разберётся и свяжется с вами.")
                    .font(.aaBodySmall)
                    .foregroundStyle(Palette.textSecondary)
            }
            Section {
                Picker(selection: $viewModel.category) {
                    ForEach(ClaimCategory.selectable, id: \.self) { category in
                        Label(category.title, systemImage: category.symbol)
                            .tag(Optional(category))
                    }
                } label: {
                    Text("Что случилось")
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: viewModel.category) { _, _ in
                    Haptics.play(.selection)
                    viewModel.clearError(.category)
                }
                if let error = viewModel.errors[.category] {
                    ClaimFieldError(text: error, shake: viewModel.shake)
                }
            } header: {
                Text("Что случилось")
            }
            Section {
                TextField(text: $viewModel.text, axis: .vertical) {
                    Text("Опишите, что пошло не так: когда, что именно, кто был на площадке")
                }
                .lineLimit(4...10)
                .focused($isTextFocused)
                .onChange(of: viewModel.text) { _, newValue in
                    viewModel.clearError(.description)
                    if newValue.count > ClaimFormViewModel.descriptionLimit {
                        viewModel.text = String(newValue.prefix(ClaimFormViewModel.descriptionLimit))
                    }
                }
                if let error = viewModel.errors[.description] {
                    ClaimFieldError(text: error, shake: viewModel.shake)
                }
            } header: {
                Text("Описание")
            } footer: {
                Text(verbatim: "\(viewModel.text.count) / \(ClaimFormViewModel.descriptionLimit)")
            }
            Section {
                Picker(selection: $viewModel.contact) {
                    ForEach(ContactPreference.selectable, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Text("Как с вами связаться")
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: viewModel.contact) { _, _ in Haptics.play(.selection) }
            } header: {
                Text("Как с вами связаться")
            }
            Section {
                InfoNote(
                    title: String(localized: "Фото можно будет отправить в чат"),
                    message: String(localized: "Когда менеджер примет претензию, здесь появится чат в Вызов Чате — туда удобно прислать фото и видео."),
                    systemImage: "camera"
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if let error = viewModel.generalError {
                Section {
                    ClaimFieldError(text: error, shake: viewModel.shake)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                isTextFocused = false
                Task { await viewModel.submit() }
            } label: {
                if viewModel.isSending { ProgressView().tint(.white) } else { Text("Отправить претензию") }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54, radius: Radius.md, font: .aaSubmit))
            .disabled(viewModel.isSending)
            .accessibilityIdentifier("claim.submit")
            .padding(.horizontal, Spacing.gutterProduct)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .stickyBottomBarBackground()
        }
    }

    private var sent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.bubble.fill")
                .font(.system(size: 52))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text("Претензия отправлена")
                .font(.aaCartTitle)
                .foregroundStyle(Palette.textProduct)
            Text("Менеджер свяжется с вами в течение рабочего дня. Когда претензию примут, в заказе появится кнопка чата.")
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
    }
}

private struct ClaimFieldError: View {
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

// MARK: - Карточка претензии в заказе

struct ClaimStatusCard: View {
    let claim: OrderClaim

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: claim.category.symbol)
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    Text(claim.categoryLabel ?? claim.category.title)
                        .font(BrandFont.golos(15, .semibold, relativeTo: .headline))
                        .foregroundStyle(Palette.textProduct)
                }
                Spacer(minLength: 8)
                statusPill
            }
            Text(claim.description)
                .font(.aaBodySmall)
                .foregroundStyle(Palette.text)
                .lineLimit(3)
            Text("Создана \(DateText.dateTime(claim.createdAt))")
                .font(.aaCaption)
                .foregroundStyle(Palette.textSecondary)
            if let comment = claim.managerComment, !comment.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ответ менеджера")
                        .font(.aaInputLabel)
                        .foregroundStyle(Palette.muted)
                    Text(comment)
                        .font(.aaBodySmall)
                        .foregroundStyle(Palette.textStrong)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.accentTint06))
            }
            if claim.status == .accepted, claim.chatUrl != nil || claim.chatAppUrl != nil {
                Button {
                    Haptics.play(.selection)
                    VyzovChatLink.open(chatUrl: claim.chatUrl, appUrl: claim.chatAppUrl)
                } label: {
                    Label("Открыть Вызов Чат", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .buttonStyle(PrimaryButtonStyle(height: 48, radius: Radius.md))
                .accessibilityIdentifier("orderDetail.openVyzovChat")
                Text("Чат «Жалобы» с менеджером: туда можно прислать фото и видео.")
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orderDetail.claimCard")
    }

    private var statusPill: some View {
        Text(claim.statusLabel ?? claim.status.title)
            .font(BrandFont.golos(12, .semibold, relativeTo: .caption))
            .foregroundStyle(Palette.textStrong)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(statusColor.opacity(0.14)))
            .overlay(Capsule().strokeBorder(statusColor.opacity(0.35), lineWidth: 1))
    }

    private var statusColor: Color {
        switch claim.status {
        case .submitted: return Palette.warning
        case .accepted: return Palette.accent
        case .resolved: return Palette.success
        case .rejected, .unknown: return Palette.textTertiary
        }
    }
}

/// Открыть чат «Жалобы»: приложение Вызов Чат (vyzovchat://join/<token>), если установлено,
/// иначе веб-версия по https.
@MainActor
enum VyzovChatLink {
    static func open(chatUrl: String?, appUrl: String?) {
        let app = UIApplication.shared
        if let raw = appUrl, let url = URL(string: raw), app.canOpenURL(url) {
            app.open(url)
            return
        }
        guard let raw = chatUrl, let web = URL(string: raw) else { return }
        if let appURL = appURL(fromWeb: web), app.canOpenURL(appURL) {
            app.open(appURL)
            return
        }
        app.open(web)
    }

    /// https://vyzovchat.ru/join/<token> → vyzovchat://join/<token>
    static func appURL(fromWeb url: URL) -> URL? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "join",
              let token = parts[1].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !token.isEmpty else { return nil }
        return URL(string: "vyzovchat://join/\(token)")
    }
}
