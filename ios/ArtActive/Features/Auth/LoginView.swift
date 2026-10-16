import Observation
import SwiftUI

@MainActor
@Observable
final class LoginViewModel {
    enum Step: Equatable { case phone, code }

    var step: Step = .phone
    var phone = ""
    var code = ""
    private(set) var codeLength = 6
    private(set) var resendIn = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var shake = 0
    private(set) var isDone = false

    @ObservationIgnored private let auth: AuthStore
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    static let defaultResend = 60

    init(auth: AuthStore) {
        self.auth = auth
    }

    var canRequest: Bool { PhoneFormatter.isMobile(phone) && !isLoading }

    func requestCode() async {
        guard let e164 = PhoneFormatter.e164(phone), PhoneFormatter.isMobile(phone) else {
            fail(String(localized: "Введите мобильный номер: +7 (9XX) XXX-XX-XX"))
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await auth.requestCode(phone: e164)
            codeLength = min(max(response.codeLength ?? 6, 4), 8)
            code = ""
            step = .code
            startTimer(response.resendIn ?? Self.defaultResend)
        } catch {
            fail(Self.message(for: error))
        }
    }

    /// Вызывается при изменении кода; полный код отправляется автоматически.
    func codeChanged() async {
        errorMessage = nil
        guard code.count == codeLength, !isLoading else { return }
        Haptics.play(.codeComplete)
        await verify()
    }

    private func verify() async {
        guard let e164 = PhoneFormatter.e164(phone) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await auth.verify(phone: e164, code: code)
            timerTask?.cancel()
            isDone = true
        } catch {
            code = ""
            fail(Self.message(for: error))
        }
    }

    func changePhone() {
        timerTask?.cancel()
        step = .phone
        code = ""
        errorMessage = nil
    }

    private func startTimer(_ seconds: Int) {
        timerTask?.cancel()
        resendIn = max(seconds, 0)
        timerTask = Task { [weak self] in
            while let self, self.resendIn > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.resendIn -= 1
            }
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        shake += 1
        Haptics.play(.error)
    }

    static func message(for error: Error) -> String {
        guard let api = error as? APIError else { return error.userMessage }
        if case let .server(status, code, message, _) = api {
            if status == 503 || code == "sms_unavailable" {
                return String(localized: "Не удалось отправить SMS. Попробуйте позже или позвоните нам.")
            }
            if status == 429 {
                return message.isEmpty ? String(localized: "Слишком много попыток. Подождите немного.") : message
            }
        }
        if api.statusCode == 503 { return String(localized: "Не удалось отправить SMS. Попробуйте позже или позвоните нам.") }
        return api.userMessage
    }
}

/// Вход: телефон с маской → код из SMS (`.oneTimeCode`), таймер повтора.
/// Гость может всё до оформления — вход нужен для заявки и истории заказов.
struct LoginView: View {
    @State private var viewModel: LoginViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: LoginViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image("LogoMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    if viewModel.step == .phone {
                        phoneStep.transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
                    } else {
                        codeStep.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)).combined(with: .opacity))
                    }
                    if let error = viewModel.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.aaCaption)
                            .foregroundStyle(Palette.error)
                            .modifier(ShakeEffect(shakes: CGFloat(viewModel.shake)))
                            .animation(.default, value: viewModel.shake)
                    }
                }
                .padding(Spacing.gutterProduct)
                .animation(Motion.slow(reduceMotion), value: viewModel.step)
            }
            .background(Palette.page)
            .navigationTitle(Text("Вход"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .onChange(of: viewModel.isDone) { _, done in
                if done { dismiss() }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(viewModel.isLoading)
    }

    private var phoneStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Войдите по номеру телефона")
                .font(.aaCartTitle)
                .foregroundStyle(Palette.textProduct)
            Text("Пришлём код в SMS. Корзину можно собирать и без входа — он нужен, чтобы оставить заявку и видеть свои заказы.")
                .font(.aaBodySmall)
                .foregroundStyle(Palette.textSecondary)
            FormField(label: String(localized: "Мобильный телефон"), error: nil, shakeTrigger: viewModel.shake) {
                PhoneTextField(text: $viewModel.phone, placeholder: "+7 (999) 999-99-99", autoFocus: true) {
                    Task { await viewModel.requestCode() }
                }
            }
            Button {
                Task { await viewModel.requestCode() }
            } label: {
                if viewModel.isLoading { ProgressView().tint(.white) } else { Text("Получить код") }
            }
            .buttonStyle(PrimaryButtonStyle(height: 54, radius: Radius.md, font: .aaSubmit))
            .disabled(!viewModel.canRequest)
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Введите код из SMS")
                .font(.aaCartTitle)
                .foregroundStyle(Palette.textProduct)
            Text("Отправили на \(viewModel.phone)")
                .font(.aaBodySmall)
                .foregroundStyle(Palette.textSecondary)

            ZStack {
                HStack(spacing: 8) {
                    ForEach(0..<viewModel.codeLength, id: \.self) { index in
                        CodeCell(
                            digit: digit(at: index),
                            isActive: index == viewModel.code.count && !viewModel.isLoading,
                            isError: viewModel.errorMessage != nil
                        )
                    }
                }
                .modifier(ShakeEffect(shakes: CGFloat(viewModel.shake)))
                .animation(.default, value: viewModel.shake)
                OneTimeCodeTextField(code: $viewModel.code, length: viewModel.codeLength)
                    .frame(height: 56)
            }
            .onChange(of: viewModel.code) { _, _ in
                Task { await viewModel.codeChanged() }
            }

            if viewModel.isLoading {
                ProgressView().tint(Palette.accent).frame(maxWidth: .infinity)
            }

            HStack {
                if viewModel.resendIn > 0 {
                    Text("Повторно через \(viewModel.resendIn) с")
                        .font(.aaBodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .contentTransition(.numericText(countsDown: true))
                        .monospacedDigit()
                } else {
                    Button("Отправить код ещё раз") {
                        Task { await viewModel.requestCode() }
                    }
                    .buttonStyle(LinkButtonStyle())
                }
                Spacer()
                Button("Изменить номер") { viewModel.changePhone() }
                    .buttonStyle(LinkButtonStyle(font: .aaBodySmall))
            }
        }
    }

    private func digit(at index: Int) -> String? {
        let chars = Array(viewModel.code)
        return index < chars.count ? String(chars[index]) : nil
    }
}

private struct CodeCell: View {
    let digit: String?
    let isActive: Bool
    let isError: Bool

    var body: some View {
        Text(digit ?? "")
            .font(BrandFont.golos(24, .bold, relativeTo: .title2))
            .foregroundStyle(Palette.textProduct)
            .frame(maxWidth: 52, minHeight: 56)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(Palette.surfaceMuted))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .strokeBorder(isError ? Palette.error : (isActive ? Palette.accent : .clear), lineWidth: 1.5)
            )
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.15), value: digit)
            .accessibilityHidden(true)
    }
}
