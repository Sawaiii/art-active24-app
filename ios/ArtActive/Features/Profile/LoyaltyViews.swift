import SwiftUI

/// Карточка «Скидка постоянного клиента» в профиле: текущий процент, прогресс до следующего уровня.
struct LoyaltyCard: View {
    let loyalty: Loyalty

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Скидка постоянного клиента")
                        .font(BrandFont.golos(15, .semibold, relativeTo: .headline))
                        .foregroundStyle(Palette.textProduct)
                    if loyalty.personal != nil {
                        Label("Персональная скидка", systemImage: "star.circle.fill")
                            .font(BrandFont.golos(12, .medium, relativeTo: .caption))
                            .foregroundStyle(Palette.accent)
                    }
                }
                Spacer(minLength: 8)
                Text(verbatim: "\(loyalty.percent)%")
                    .font(BrandFont.golos(34, .bold, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.accent)
                    .monospacedDigit()
            }
            if loyalty.nextTier != nil || loyalty.personal == nil {
                ProgressView(value: loyalty.progressToNext)
                    .tint(Palette.accent)
                    .accessibilityHidden(true)
            }
            Text(progressText)
                .font(.aaBodySmall)
                .foregroundStyle(Palette.textStrong)
            Text("Сумма заказов: \(Money.rub(loyalty.spent))")
                .font(.aaCaption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Открыть уровни скидки"))
    }

    private var progressText: String {
        guard let next = loyalty.nextTier else { return String(localized: "Максимальный уровень") }
        let nextPercentText = "\(next.percent)%"
        return String(localized: "До \(nextPercentText) осталось \(Money.rub(next.remaining))")
    }
}

/// Скелетон карточки скидки.
struct LoyaltyCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SkeletonBlock(width: 180, height: 16)
                Spacer()
                SkeletonBlock(width: 60, height: 32)
            }
            SkeletonBlock(height: 6, radius: 3)
            SkeletonBlock(width: 200, height: 12)
        }
        .padding(.vertical, 6)
        .shimmering()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Загрузка"))
    }
}

/// Лестница уровней: пороги суммы завершённых заказов → процент; текущий уровень отмечен.
struct LoyaltyLadderSheet: View {
    let loyalty: Loyalty
    @Environment(\.dismiss) private var dismiss

    init(loyalty: Loyalty) {
        self.loyalty = loyalty
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "\(loyalty.percent)%")
                            .font(BrandFont.golos(40, .bold, relativeTo: .largeTitle))
                            .foregroundStyle(Palette.accent)
                        Text("Сумма завершённых заказов: \(Money.rub(loyalty.spent))")
                            .font(.aaBodySmall)
                            .foregroundStyle(Palette.textStrong)
                        if let personal = loyalty.personal {
                            let personalPercentText = "\(personal.percent)%"
                            Text("Менеджер назначил вам персональную скидку \(personalPercentText) — она действует вместо уровня.")
                                .font(.aaCaption)
                                .foregroundStyle(Palette.textSecondary)
                            if let note = personal.note, !note.isEmpty {
                                Text(note).font(.aaCaption).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    ForEach(Array(loyalty.tiers.enumerated()), id: \.offset) { _, tier in
                        let isCurrent = tier.threshold == loyalty.tier.threshold && loyalty.personal == nil
                        HStack(spacing: 12) {
                            Image(systemName: isCurrent ? "checkmark.circle.fill" : (loyalty.spent >= tier.threshold ? "checkmark.circle" : "circle"))
                                .foregroundStyle(isCurrent || loyalty.spent >= tier.threshold ? Palette.accent : Palette.textTertiary)
                                .accessibilityHidden(true)
                            Text(tier.threshold == 0 ? String(localized: "С первого заказа") : String(localized: "от \(Money.rub(tier.threshold))"))
                                .font(BrandFont.golos(15, isCurrent ? .semibold : .regular, relativeTo: .body))
                                .foregroundStyle(Palette.textProduct)
                            Spacer()
                            Text(verbatim: "\(tier.percent)%")
                                .font(BrandFont.golos(16, .semibold, relativeTo: .body))
                                .foregroundStyle(isCurrent ? Palette.accent : Palette.textStrong)
                                .monospacedDigit()
                        }
                        .frame(minHeight: 36)
                        .listRowBackground(isCurrent ? Palette.accentTint08 : Palette.surface)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(isCurrent ? Text("Ваш уровень") : Text(verbatim: ""))
                    }
                } header: {
                    Text("Уровни")
                } footer: {
                    Text("Уровень считается по сумме всех завершённых заказов. Скидка применяется автоматически — в корзине и при оформлении заявки.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Text("Скидка постоянного клиента"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("loyalty.sheet")
    }
}
