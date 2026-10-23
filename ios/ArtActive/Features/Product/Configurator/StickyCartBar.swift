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
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Ширина кнопки действия; на accessibility-размерах бар складывается в колонку.
    private var actionWidth: CGFloat? { typeSize.isAccessibilitySize ? nil : 150 }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 10))
        VStack(alignment: .leading, spacing: 8) {
            if let error = viewModel.lastError {
                Label {
                    Text(error).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.aaCaption)
                .foregroundStyle(Palette.error)
                .transition(.opacity)
            }
            GlassGroup(spacing: 10) {
                layout {
                    priceBox
                    actionArea
                }
            }
        }
        // Бар липкий — не даём ему съесть экран на самых крупных размерах.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, Spacing.gutterProduct)
        // Бейдж срока теперь внутри ценового блока — сверху обычный отступ сетки.
        .padding(.top, 12)
        .padding(.bottom, 8)
        .stickyBottomBarBackground()
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
                    .foregroundStyle(Palette.onAccent)
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
        .onChange(of: viewModel.lastError) { _, error in
            // Ошибка появляется вне фокуса VoiceOver — озвучиваем.
            if let error { AccessibilityNotification.Announcement(error).post() }
        }
        .animation(Motion.snappy(reduceMotion), value: viewModel.isInCart)
    }

    // MARK: - Цена

    private var priceBox: some View {
        Button {
            Haptics.play(.selection)
            isBreakdownPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                // Бейдж срока — в строке лейбла («Аренда [3 дня]»), а не поверх него.
                HStack(spacing: 6) {
                    Text(viewModel.priceLabel)
                        .font(.pPriceLabel)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    if let badge = viewModel.badge {
                        DayBadge(text: badge)
                            .lineLimit(1)
                            .fixedSize()
                            .animation(Motion.snappy(reduceMotion), value: badge)
                    }
                }
                priceLine
                if let hint = viewModel.hint {
                    Text(hint)
                        .font(.configHint)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())
                } else if viewModel.isInCart, let total = viewModel.price?.total, viewModel.mode != .cateringMenu {
                    Text("Итого \(Money.rub(total))")
                        .font(.configHint)
                        .foregroundStyle(Palette.textSecondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Показать расшифровку итога"))
        .accessibilityIdentifier("cartbar.total")
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
                    Text("В корзине ›")
                        .font(BrandFont.inter(12, .semibold, relativeTo: .caption))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        // Визуально компактная ссылка, зона нажатия 44 pt по высоте.
                        .contentShape(Rectangle().inset(by: -6))
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
            .frame(width: actionWidth)
        } else {
            Button {
                viewModel.addToCart()
            } label: {
                Text("В корзину")
            }
            .buttonStyle(PrimaryButtonStyle(height: 54, radius: Radius.md, font: .pCartButton))
            .accessibilityIdentifier("cartbar.add")
            .frame(width: actionWidth)
            .onAppear { Haptics.prepare(.addedToCart) }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    /// «Полёт в таб»: значок корзины улетает к табу «Корзина» (центр таб-бара).
    private func flyToCart() {
        guard !reduceMotion, !typeSize.isAccessibilitySize, barWidth > 0 else { return }
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
                                    .font(row.emphasized ? BrandFont.inter(17, .bold, relativeTo: .headline) : .pBody)
                                    .foregroundStyle(row.emphasized ? Palette.textProduct : Palette.textSecondary)
                                Spacer(minLength: 12)
                                Text(row.value)
                                    .font(row.emphasized ? BrandFont.inter(17, .bold, relativeTo: .headline) : BrandFont.inter(15, .medium, relativeTo: .subheadline))
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
                        .accessibilityIdentifier("breakdown.done")
                }
            }
        }
    }
}
