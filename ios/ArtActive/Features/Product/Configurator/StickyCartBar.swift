import SwiftUI

/// Липкий нижний бар карточки: бейдж срока, лейбл, цена (numericText), подсказка
/// «с 2-го дня — X ₽» / «доп. час — X ₽», «В корзину» → степпер, «Итого» с расшифровкой.
/// На iOS 26 — Liquid Glass, ниже — material.
struct StickyCartBar: View {
    let viewModel: ConfiguratorViewModel

    @State private var isBreakdownPresented = false
    @State private var flyOffset: CGSize = .zero
    @State private var flyVisible = false
    @State private var barWidth: CGFloat = 0
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = viewModel.lastError {
                Text(error)
                    .font(.aaCaption)
                    .foregroundStyle(Palette.error)
                    .transition(.opacity)
            }
            GlassGroup(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    priceBox
                    actionArea
                }
            }
        }
        .padding(.horizontal, Spacing.gutterProduct)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { barWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in barWidth = width }
            }
        )
        .overlay(alignment: .bottomTrailing) {
            if flyVisible {
                Image(systemName: "cart.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Palette.accent))
                    .padding(.trailing, Spacing.gutterProduct + 75 - 18)
                    .padding(.bottom, 8 + 27 - 18)
                    .offset(flyOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .sheet(isPresented: $isBreakdownPresented) {
            BreakdownSheet(sections: viewModel.breakdown)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: viewModel.flyPulse) { _, _ in flyToCart() }
        .animation(Motion.snappy(reduceMotion), value: viewModel.isInCart)
    }

    // MARK: - Цена

    private var priceBox: some View {
        Button {
            Haptics.play(.selection)
            isBreakdownPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.priceLabel)
                    .font(.pPriceLabel)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                priceLine
                if let hint = viewModel.hint {
                    Text(hint)
                        .font(.pPriceHint)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                } else if viewModel.isInCart, let total = viewModel.price?.total, viewModel.mode != .cateringMenu {
                    Text("Итого \(Money.rub(total))")
                        .font(.pPriceHint)
                        .foregroundStyle(Palette.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .brandGlass(in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous), tint: Palette.surfaceMuted.opacity(0.5))
            .overlay(alignment: .topLeading) {
                if let badge = viewModel.badge {
                    DayBadge(text: badge)
                        .offset(x: 2, y: -14)
                        .animation(Motion.snappy(reduceMotion), value: badge)
                }
            }
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Показать расшифровку итога"))
    }

    @ViewBuilder
    private var priceLine: some View {
        if let price = viewModel.price, price.onRequest {
            Text("по запросу")
                .font(.pPriceAmount)
                .foregroundStyle(Palette.textProduct)
        } else if let amount = viewModel.barAmount {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if viewModel.showsFrom {
                    Text("от").font(.pPriceLabel).foregroundStyle(Palette.textProduct)
                }
                Text(Money.rub(amount))
                    .font(.pPriceAmount)
                    .tracking(-0.45)
                    .foregroundStyle(Palette.textProduct)
                    .contentTransition(.numericText(value: Double(amount)))
                    .animation(Motion.snappy(reduceMotion), value: amount)
                if let postfix = viewModel.postfix, viewModel.mode != .cateringMenu {
                    Text(postfix).font(.pPriceLabel).foregroundStyle(Palette.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else {
            Text(verbatim: "—").font(.pPriceAmount).foregroundStyle(Palette.textSecondary)
        }
    }

    // MARK: - В корзину / степпер

    @ViewBuilder
    private var actionArea: some View {
        if let line = viewModel.cartLine, viewModel.mode != .cateringMenu {
            VStack(spacing: 6) {
                QtyStepper(
                    value: line.qty,
                    minimum: viewModel.minQty,
                    unit: nil,
                    removesAtMinimum: true,
                    onChange: { viewModel.setCartQty($0) },
                    onRemove: { viewModel.removeFromCart() }
                )
                Button {
                    router.selectedTab = .cart
                } label: {
                    Text("В корзине ›").font(BrandFont.inter(12, .semibold))
                }
                .buttonStyle(LinkButtonStyle())
            }
            .frame(minWidth: 150)
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        } else if viewModel.cartLine != nil {
            Button {
                router.selectedTab = .cart
            } label: {
                Label("В корзине", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle(height: 54, radius: Radius.md, font: .pCartButton, shadow: false))
            .frame(width: 150)
        } else {
            Button {
                viewModel.addToCart()
            } label: {
                Text("В корзину")
            }
            .buttonStyle(PrimaryButtonStyle(height: 54, radius: Radius.md, font: .pCartButton))
            .frame(width: 150)
            .onAppear { Haptics.prepare(.addedToCart) }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    /// «Полёт в таб»: значок корзины улетает к табу «Корзина» (центр таб-бара).
    private func flyToCart() {
        guard !reduceMotion, barWidth > 0 else { return }
        // Кнопка справа (ширина 150), таб «Корзина» — третий из пяти, т.е. по центру.
        let buttonMidX = barWidth - Spacing.gutterProduct - 75
        flyOffset = .zero
        flyVisible = true
        withAnimation(.easeIn(duration: 0.45)) {
            flyOffset = CGSize(width: barWidth / 2 - buttonMidX, height: 90)
        } completion: {
            flyVisible = false
            flyOffset = .zero
        }
    }
}

/// Расшифровка «Итого»: конфигурация, стоимость, допы (не × кол-во и дни).
struct BreakdownSheet: View {
    let sections: [BreakdownSection]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.title)
                                    .font(row.emphasized ? BrandFont.inter(17, .bold) : .pBody)
                                    .foregroundStyle(row.emphasized ? Palette.textProduct : Palette.textSecondary)
                                Spacer(minLength: 12)
                                Text(row.value)
                                    .font(row.emphasized ? BrandFont.inter(17, .bold) : BrandFont.inter(15, .medium))
                                    .foregroundStyle(Palette.textProduct)
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        if section.rows.count > 1 || !(section.rows.first?.emphasized ?? false) {
                            Text(section.title)
                        }
                    } footer: {
                        if let note = section.note { Text(note) }
                    }
                }
                Section {
                    Text("Клиентский расчёт — предварительный. Итоговую сумму пересчитает сервер в корзине, а менеджер подтвердит после заявки.")
                        .font(.aaCaption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .navigationTitle(Text("Итого"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
