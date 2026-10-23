import SwiftUI

/// Профиль: вход/данные, «Мои заказы» с бейджем изменений, избранное, контакты,
/// доставка, условия аренды, связь с менеджером, выход.
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(AuthStore.self) private var auth
    @Environment(OrdersStore.self) private var orders
    @Environment(InfoStore.self) private var info
    @Environment(FavoritesStore.self) private var favorites
    @State private var isSignOutConfirming = false
    @State private var isDemoResetConfirming = false
    @State private var isLoyaltyPresented = false

    var body: some View {
        List {
            if env.isDemoMode {
                demoSection
            }
            accountSection
            if auth.isLoggedIn {
                loyaltySection
            }
            Section {
                NavigationLink(value: Route.orders) {
                    row(
                        String(localized: "Мои заказы"),
                        systemImage: "shippingbox",
                        badge: orders.unseenCount,
                        trailing: auth.isLoggedIn ? nil : String(localized: "После входа")
                    )
                }
                .accessibilityIdentifier("profile.orders")
                .disabled(!auth.isLoggedIn)
                NavigationLink(value: Route.favorites) {
                    row(String(localized: "Избранное"), systemImage: "heart", badge: 0, trailing: favorites.items.isEmpty ? nil : "\(favorites.items.count)")
                }
            }
            Section {
                NavigationLink(value: Route.info(.contacts)) {
                    row(String(localized: "Контакты"), systemImage: "mappin.and.ellipse", badge: 0)
                }
                NavigationLink(value: Route.info(.delivery)) {
                    row(String(localized: "Доставка и оплата"), systemImage: "truck.box", badge: 0)
                }
                NavigationLink(value: Route.info(.rentalTerms)) {
                    row(String(localized: "Условия аренды"), systemImage: "doc.text", badge: 0)
                }
            } header: {
                Text("Информация")
            }
            Section {
                ContactButtonsRow()
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                if let phone = info.info.phone {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PhoneFormatter.display(phone))
                            .font(BrandFont.golos(17, .semibold))
                            .foregroundStyle(Palette.textProduct)
                        if let hint = info.info.phoneHint {
                            Text(hint).font(.aaCaption).foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            } header: {
                Text("Связь с менеджером")
            }
            if auth.isLoggedIn {
                Section {
                    Button(role: .destructive) {
                        isSignOutConfirming = true
                    } label: {
                        Text("Выйти")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Профиль"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            Haptics.play(.refresh)
            await auth.refreshUser()
            await orders.load()
            if auth.isLoggedIn { await env.loyalty.load() }
        }
        .confirmationDialog(Text("Выйти из аккаунта?"), isPresented: $isSignOutConfirming, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                Task { await auth.signOut() }
            }
        } message: {
            Text("Корзина и избранное на этом устройстве будут очищены.")
        }
        .confirmationDialog(Text("Сбросить демо-данные?"), isPresented: $isDemoResetConfirming, titleVisibility: .visible) {
            Button("Сбросить", role: .destructive) {
                Task { await env.resetDemoData() }
            }
        } message: {
            Text("Заказы, корзина, избранное и вход на этом телефоне будут удалены.")
        }
        .task {
            if auth.isLoggedIn, orders.status == .idle { await orders.load() }
            if auth.isLoggedIn, env.loyalty.status == .idle { await env.loyalty.load() }
        }
        .sheet(isPresented: $isLoyaltyPresented) {
            if let loyalty = env.loyalty.loyalty {
                LoyaltyLadderSheet(loyalty: loyalty)
            }
        }
    }

    /// Демо-режим: встроенный каталог, данные на телефоне, статусы двигаются сами.
    private var demoSection: some View {
        Section {
            InfoNote(
                title: String(localized: "Демо-режим: встроенный каталог, заказы хранятся на телефоне, статусы двигаются автоматически"),
                systemImage: "sparkles"
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            Button(role: .destructive) {
                isDemoResetConfirming = true
            } label: {
                Label("Сбросить демо-данные", systemImage: "arrow.counterclockwise")
            }
        }
    }

    /// «Скидка постоянного клиента»: процент и прогресс; тап — лестница уровней.
    @ViewBuilder
    private var loyaltySection: some View {
        if let loyalty = env.loyalty.loyalty {
            Section {
                Button {
                    Haptics.play(.selection)
                    isLoyaltyPresented = true
                } label: {
                    LoyaltyCard(loyalty: loyalty)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.loyalty")
            }
        } else if env.loyalty.status == .loading || env.loyalty.status == .idle {
            Section {
                LoyaltyCardSkeleton()
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if let user = auth.user {
                NavigationLink(value: Route.profileEdit) {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.name?.isEmpty == false ? (user.name ?? "") : String(localized: "Без имени"))
                                .font(BrandFont.golos(17, .semibold))
                                .foregroundStyle(Palette.textProduct)
                            Text(PhoneFormatter.display(user.phone))
                                .font(.aaBodySmall)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Войдите, чтобы оставлять заявки и следить за статусом заказов")
                        .font(.aaBodySmall)
                        .foregroundStyle(Palette.textSecondary)
                    Button("Войти по номеру телефона") {
                        env.router.requireLogin(isLoggedIn: false) {}
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 48, radius: Radius.md))
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func row(_ title: String, systemImage: String, badge: Int, trailing: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Palette.accent)
                .frame(width: 26)
            Text(title).foregroundStyle(Palette.textProduct)
            Spacer()
            if badge > 0 {
                CounterBadge(count: badge)
                    .accessibilityLabel(Text("Есть изменения: \(badge)"))
            } else if let trailing {
                Text(trailing).foregroundStyle(Palette.textSecondary)
            }
        }
        .font(BrandFont.golos(16))
    }
}

// MARK: - Данные профиля

@MainActor
@Observable
final class ProfileEditViewModel {
    var name: String
    var email: String
    var company: String
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var saved = false

    @ObservationIgnored private let auth: AuthStore

    init(auth: AuthStore) {
        self.auth = auth
        name = auth.user?.name ?? ""
        email = auth.user?.email ?? ""
        company = auth.user?.company ?? ""
    }

    var phone: String { auth.user.map { PhoneFormatter.display($0.phone) } ?? "" }

    func save() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if !trimmedEmail.isEmpty, !Validation.isEmail(trimmedEmail) {
            errorMessage = String(localized: "Проверьте e-mail")
            Haptics.play(.error)
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await auth.updateProfile(ProfilePatch(
                name: String(name.trimmingCharacters(in: .whitespaces).prefix(100)),
                email: trimmedEmail.isEmpty ? nil : String(trimmedEmail.prefix(150)),
                company: company.isEmpty ? nil : String(company.prefix(150))
            ))
            saved = true
            Haptics.play(.success)
        } catch {
            errorMessage = error.userMessage
            Haptics.play(.error)
        }
    }
}

struct ProfileEditView: View {
    @State private var viewModel: ProfileEditViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field { case name, email, company }

    init(viewModel: ProfileEditViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                TextField(text: $viewModel.name) { Text("Имя") }
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
                TextField(text: $viewModel.email) { Text("E-mail") }
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .company }
                TextField(text: $viewModel.company) { Text("Компания") }
                    .textContentType(.organizationName)
                    .focused($focus, equals: .company)
                    .submitLabel(.done)
                    .onSubmit { focus = nil }
            } header: {
                Text("Мои данные")
            }
            Section {
                LabeledContent {
                    Text(viewModel.phone)
                } label: {
                    Text("Телефон")
                }
            } footer: {
                Text("Номер телефона — логин, его сменить нельзя.")
            }
            if let error = viewModel.errorMessage {
                Section { Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Palette.error) }
            }
        }
        .navigationTitle(Text("Мои данные"))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    Task { await viewModel.save() }
                } label: {
                    if viewModel.isSaving { ProgressView() } else { Text("Сохранить") }
                }
                .accessibilityLabel(Text("Сохранить"))
                .disabled(viewModel.isSaving)
            }
        }
        .onChange(of: viewModel.saved) { _, saved in
            if saved { dismiss() }
        }
    }
}

// MARK: - Контакты / доставка / условия

struct InfoPageView: View {
    let page: InfoPage
    @Environment(InfoStore.self) private var info

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch page {
                case .contacts:
                    contacts
                case .delivery:
                    htmlOrPlaceholder(info.info.deliveryHtml)
                case .rentalTerms:
                    htmlOrPlaceholder(info.info.rentalTermsHtml)
                }
            }
            .padding(Spacing.gutter)
        }
        .background(Palette.page)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await info.load() }
    }

    private var title: Text {
        switch page {
        case .contacts: return Text("Контакты")
        case .delivery: return Text("Доставка и оплата")
        case .rentalTerms: return Text("Условия аренды")
        }
    }

    @ViewBuilder
    private func htmlOrPlaceholder(_ html: String?) -> some View {
        if let html, !html.isEmpty {
            HTMLText(html: html)
        } else {
            EmptyStateView(
                systemImage: "doc.text",
                title: String(localized: "Информация загружается"),
                message: String(localized: "Потяните вниз, чтобы обновить, или свяжитесь с менеджером.")
            )
        }
    }

    private var contacts: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let phone = info.info.phone {
                contactRow(title: String(localized: "Телефон"), value: PhoneFormatter.display(phone), note: info.info.phoneHint)
            }
            if let email = info.info.email {
                contactRow(title: String(localized: "E-mail"), value: email, note: nil)
            }
            if let address = info.info.address {
                contactRow(title: String(localized: "Адрес"), value: address, note: nil)
            }
            if let pickup = info.info.pickupAddress {
                contactRow(title: String(localized: "Самовывоз"), value: pickup, note: info.info.pickupHours)
            }
            if let rating = info.info.rating, let value = rating.value {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill").foregroundStyle(Palette.saleYellow)
                    Text(verbatim: value.formatted(.number.precision(.fractionLength(1))))
                        .font(BrandFont.golos(16, .bold))
                    if let reviews = rating.reviews {
                        Text("\(reviews)+ отзывов").foregroundStyle(Palette.textSecondary)
                    }
                    if let source = rating.source {
                        Text(source).foregroundStyle(Palette.textSecondary)
                    }
                }
                .font(.aaBodySmall)
            }
            ContactButtonsRow()
            if let socials = info.info.socials, !socials.isEmpty {
                FlowLayout {
                    ForEach(Array(socials.enumerated()), id: \.offset) { _, social in
                        if let url = social.url?.resolvedURL {
                            Link(destination: url) {
                                Text(social.name ?? url.host ?? "")
                                    .font(.aaChip)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(Palette.surfaceMuted))
                            }
                        }
                    }
                }
            }
        }
    }

    private func contactRow(title: String, value: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.aaInputLabel).foregroundStyle(Palette.muted)
            Text(value)
                .font(BrandFont.golos(17, .semibold))
                .foregroundStyle(Palette.textProduct)
                .textSelection(.enabled)
            if let note { Text(note).font(.aaCaption).foregroundStyle(Palette.textSecondary) }
        }
        .accessibilityElement(children: .combine)
    }
}
