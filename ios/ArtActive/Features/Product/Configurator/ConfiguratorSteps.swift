import SwiftUI

// MARK: - Комплекты: карусель + «Показать все»

struct ComplectsStep: View {
    let viewModel: ConfiguratorViewModel
    @State private var showAll = false
    @State private var infoComplect: Complect?

    private var complects: [Complect] { viewModel.product.complects }

    /// Кнопка «i» — только если есть описание или PDF.
    private func infoAction(for complect: Complect) -> (() -> Void)? {
        guard complect.textHtml?.isEmpty == false || complect.pdfUrl != nil else { return nil }
        return { infoComplect = complect }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepLabel(title: viewModel.configurator.complectsTitle())
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(complects) { complect in
                            ComplectCard(
                                complect: complect,
                                priceType: viewModel.state?.priceType ?? .rent,
                                isSelected: complect.id == viewModel.state?.complectId,
                                onInfo: infoAction(for: complect)
                            ) {
                                viewModel.selectComplect(complect.id)
                            }
                            .id(complect.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, Spacing.gutterProduct)
                }
                .scrollTargetBehavior(.viewAligned)
                .padding(.horizontal, -Spacing.gutterProduct)
                .onChange(of: viewModel.state?.complectId) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            if complects.count > 2 {
                HStack {
                    Spacer()
                    Button {
                        Haptics.play(.selection)
                        showAll = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Показать все \(complects.count)")
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(LinkButtonStyle(font: BrandFont.inter(14, .medium)))
                }
            }
        }
        .sheet(isPresented: $showAll) {
            AllComplectsSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $infoComplect) { complect in
            ComplectInfoSheet(complect: complect)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// `.variant-card`: h56 r12, рамка; выбран — фиолетовая рамка и тинт.
struct ComplectCard: View {
    let complect: Complect
    let priceType: PriceType
    let isSelected: Bool
    var onInfo: (() -> Void)?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                if let image = complect.image?.resolvedURL {
                    RemoteImage(url: image, contentMode: .fit, maxPixel: 160, placeholder: Palette.surface)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(complect.title)
                        .font(.pVariantTitle)
                        .foregroundStyle(Palette.textProduct)
                        .lineLimit(1)
                    if let side = complect.side(priceType) {
                        Text(ComplectPrice.text(side))
                            .font(.pVariantPrice)
                            .foregroundStyle(Palette.variantPrice)
                            .lineLimit(1)
                    } else if let subtitle = complect.subtitle {
                        Text(subtitle)
                            .font(.pVariantPrice)
                            .foregroundStyle(Palette.variantPrice)
                            .lineLimit(1)
                    }
                }
                .padding(.trailing, onInfo == nil ? 0 : 18)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? Palette.accentTint05 : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PressableStyle())
        .overlay(alignment: .topTrailing) {
            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? Palette.accent : Palette.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isSelected ? Palette.accentTint10 : Palette.surfaceMuted))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Подробнее о комплекте"))
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum ComplectPrice {
    /// «от 340 ₽ / порц.», «по запросу», «770 ₽».
    static func text(_ side: PriceSide) -> String {
        if side.onRequest == true { return String(localized: "по запросу") }
        if side.amount == 0, side.from != true { return side.label }
        let tag = PriceTag(amount: side.amount, from: side.from, unit: side.postfix, onRequest: nil)
        return Money.tag(tag)
    }
}

/// «Показать все N» — список комплектов с подробностями.
private struct AllComplectsSheet: View {
    let viewModel: ConfiguratorViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.product.complects) { complect in
                Button {
                    viewModel.selectComplect(complect.id)
                    dismiss()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        RemoteImage(url: complect.image?.resolvedURL, contentMode: .fit, maxPixel: 200, placeholder: Palette.imagePlaceholder)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(complect.title)
                                .font(BrandFont.inter(15, .semibold))
                                .foregroundStyle(Palette.textProduct)
                            if let side = complect.side(viewModel.state?.priceType ?? .rent) {
                                Text(ComplectPrice.text(side))
                                    .font(BrandFont.inter(14, .medium))
                                    .foregroundStyle(Palette.accent)
                            }
                            if let html = complect.textHtml, !html.isEmpty {
                                Text(HTMLParser.plainText(html))
                                    .font(.pStepLabel)
                                    .foregroundStyle(Palette.textSecondary)
                                    .lineLimit(3)
                            }
                        }
                        Spacer(minLength: 0)
                        if complect.id == viewModel.state?.complectId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle(Text(viewModel.configurator.complectsTitle()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

/// «i» комплекта: описание (HTML) и PDF.
private struct ComplectInfoSheet: View {
    let complect: Complect
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = complect.image?.resolvedURL {
                        RemoteImage(url: image, contentMode: .fit, maxPixel: 900, placeholder: Palette.page)
                            .frame(height: 200)
                    }
                    if let html = complect.textHtml, !html.isEmpty {
                        HTMLText(html: html)
                    }
                    if let includes = complect.includes, !includes.isEmpty {
                        BulletList(title: String(localized: "В комплекте"), items: includes)
                    }
                    if let pdf = complect.pdfUrl?.resolvedURL {
                        Button {
                            router.openWeb(pdf)
                        } label: {
                            Label("Открыть PDF", systemImage: "doc.richtext")
                        }
                        .buttonStyle(SecondaryButtonStyle(fill: Palette.surfaceMuted))
                    }
                }
                .padding(Spacing.gutterProduct)
            }
            .navigationTitle(Text(complect.title))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Список пунктов с маркерами («В комплекте», «Требования к помещению»).
struct BulletList: View {
    let title: String
    let items: [String]
    var systemImage = "checkmark"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(BrandFont.inter(15, .semibold))
                .foregroundStyle(Palette.textProduct)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.accent)
                    Text(item)
                        .font(.pBody)
                        .foregroundStyle(Palette.textProduct)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Аренда / Купить

struct PriceTypeStep: View {
    let viewModel: ConfiguratorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepLabel(title: String(localized: "Формат"))
            Picker(selection: Binding(
                get: { viewModel.state?.priceType ?? .rent },
                set: { viewModel.selectPriceType($0) }
            )) {
                ForEach(viewModel.priceTypes, id: \.self) { type in
                    Text(label(type)).tag(type)
                }
            } label: {
                Text("Формат")
            }
            .pickerStyle(.segmented)
        }
    }

    private func label(_ type: PriceType) -> String {
        viewModel.complect?.side(type)?.label
            ?? (type == .buy ? String(localized: "Купить") : String(localized: "Аренда"))
    }
}

// MARK: - Варианты / способ установки

struct SubsStep: View {
    let viewModel: ConfiguratorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let state = viewModel.state {
                StepLabel(title: viewModel.configurator.subsTitle(state))
            }
            ForEach(viewModel.subGroups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    if let title = group.title, !title.isEmpty {
                        Text(title)
                            .font(BrandFont.inter(14, .semibold))
                            .foregroundStyle(Palette.textProduct)
                    }
                    if viewModel.mode == .trampoline {
                        ForEach(group.subs) { sub in
                            InstallOptionCard(sub: sub, isSelected: sub.id == viewModel.state?.subId) {
                                viewModel.selectSub(sub.id)
                            }
                        }
                    } else {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(group.subs) { sub in
                                SubButton(
                                    sub: sub,
                                    priceType: viewModel.state?.priceType ?? .rent,
                                    isSelected: sub.id == viewModel.state?.subId
                                ) { viewModel.selectSub(sub.id) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// `.size-btn`: название + цена варианта.
private struct SubButton: View {
    let sub: Sub
    let priceType: PriceType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                    .font(BrandFont.inter(13, .semibold))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.textProduct)
                if let side = sub.side(priceType), side.amount > 0 || side.onRequest == true {
                    Text(ComplectPrice.text(side))
                        .font(.pVariantPrice)
                        .foregroundStyle(Palette.variantPrice)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .fill(isSelected ? Palette.accentTint05 : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Батут: способ установки — карточка с фото, текстом и фикс-надбавкой.
private struct InstallOptionCard: View {
    let sub: Sub
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                if let image = sub.image?.resolvedURL {
                    RemoteImage(url: image, maxPixel: 240)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sub.name)
                            .font(BrandFont.inter(15, .semibold))
                            .foregroundStyle(Palette.textProduct)
                        Spacer()
                        Text(surchargeText)
                            .font(BrandFont.inter(13, .semibold))
                            .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
                    }
                    if let text = sub.text, !text.isEmpty {
                        Text(text)
                            .font(.pStepLabel)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Palette.accent : Palette.disabled)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? Palette.accentTint05 : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent : Palette.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(PressableStyle(scale: 0.98))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var surchargeText: String {
        let flat = sub.flatSurcharge ?? 0
        return flat > 0 ? "+" + Money.rub(flat) : "+" + Money.rub(0)
    }
}

// MARK: - Время аренды

struct TimeStep: View {
    let viewModel: ConfiguratorViewModel
    let options: TimeOptions
    @State private var isCustomPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let state = viewModel.state {
                StepLabel(title: viewModel.configurator.timeTitle(state))
            }
            TimeSegmentControl(options: options.primary, selected: viewModel.state?.time) { option in
                select(option)
            }
            if !options.days.isEmpty {
                Text("Несколько дней: каждый день — плюс 30 процентов от цены 8 часов")
                    .font(.pPriceHint)
                    .foregroundStyle(Palette.textSecondary)
                TimeSegmentControl(options: options.days, selected: viewModel.state?.time) { option in
                    select(option)
                }
            }
        }
        .sheet(isPresented: $isCustomPresented) {
            CustomDaysSheet(
                minimum: options.moreMinimum,
                initial: max(viewModel.state?.time?.value ?? options.moreMinimum, options.moreMinimum)
            ) { days in
                viewModel.selectTime(TimeSelection(unit: .days, value: days))
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }

    private func select(_ option: TimeOption) {
        switch option {
        case let .value(selection):
            viewModel.selectTime(selection)
        case .more:
            Haptics.play(.selection)
            isCustomPresented = true
        }
    }
}

/// «ещё» — ввод количества дней колесом.
private struct CustomDaysSheet: View {
    let minimum: Int
    let onDone: (Int) -> Void
    @State private var days: Int
    @Environment(\.dismiss) private var dismiss

    init(minimum: Int, initial: Int, onDone: @escaping (Int) -> Void) {
        self.minimum = minimum
        self.onDone = onDone
        _days = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Picker(selection: $days) {
                ForEach(minimum...Configurator.maxDays, id: \.self) { value in
                    Text("\(value) дней").tag(value)
                }
            } label: {
                Text("Количество дней")
            }
            .pickerStyle(.wheel)
            .onChange(of: days) { _, _ in Haptics.play(.step) }
            .navigationTitle(Text("Срок аренды"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        onDone(days)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Доп. опции

struct ExtrasStep: View {
    let viewModel: ConfiguratorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StepLabel(title: String(localized: "Дополнительные опции"))
            VStack(spacing: 8) {
                ForEach(viewModel.configurator.plainExtras) { extra in
                    ExtraRow(extra: extra, viewModel: viewModel)
                }
            }
            Text("Доп. опции считаются один раз на позицию — не умножаются на количество и дни.")
                .font(.pPriceHint)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

/// `.extra-btn`: фото, название, цена, обязательность; у счётных — свой степпер.
struct ExtraRow: View {
    let extra: Extra
    let viewModel: ConfiguratorViewModel

    var body: some View {
        let isOn = viewModel.isSelected(extra: extra.id)
        HStack(spacing: 12) {
            if let image = extra.image?.resolvedURL {
                RemoteImage(url: image, maxPixel: 160)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(extra.name)
                        .font(BrandFont.inter(14, .semibold))
                        .foregroundStyle(Palette.textProduct)
                    if extra.isRequired {
                        Text("обязательно")
                            .font(BrandFont.inter(11, .semibold))
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: Radius.xs).fill(Palette.accentTint08))
                    }
                }
                Text(extra.from == true ? String(localized: "от \(Money.rub(extra.price))") : Money.rub(extra.price))
                    .font(.pVariantPrice)
                    .foregroundStyle(Palette.variantPrice)
                if let note = extra.note, !note.isEmpty {
                    Text(note)
                        .font(.pPriceHint)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if extra.isCountable, isOn {
                QtyStepper(
                    value: viewModel.extraQty(extra.id),
                    minimum: extra.isRequired ? 1 : 0,
                    removesAtMinimum: !extra.isRequired,
                    compact: true,
                    onChange: { viewModel.setExtraQty(extra.id, $0) },
                    onRemove: { viewModel.setExtraQty(extra.id, 0) }
                )
            } else {
                Image(systemName: isOn ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isOn ? Palette.accent : Palette.disabled)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isOn ? Palette.accentTint05 : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isOn ? Palette.accent.opacity(0.6) : Palette.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !(extra.isCountable && isOn) { viewModel.toggleExtra(extra.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Кейтеринг-меню

struct CateringMenuStep: View {
    let viewModel: ConfiguratorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepLabel(title: String(localized: "Состав заказа"))
            if let progress = viewModel.rewardProgress, let reward = viewModel.complect?.reward {
                RewardProgressView(progress: progress, reward: reward, menuSum: viewModel.price?.unitPrice ?? 0)
            }
            ForEach(viewModel.menuGroups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    if let title = group.title, !title.isEmpty {
                        Text(title)
                            .font(BrandFont.inter(14, .semibold))
                            .foregroundStyle(Palette.textProduct)
                    }
                    ForEach(group.rows) { row in
                        MenuRowView(row: row, qty: viewModel.menuQty(row.id)) { viewModel.setMenuQty(row.id, $0) }
                    }
                }
            }
            if let error = viewModel.validationError {
                Text(error.message)
                    .font(.aaCaption)
                    .foregroundStyle(Palette.error)
            }
        }
    }
}

private struct MenuRowView: View {
    let row: MenuRow
    let qty: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(BrandFont.inter(14, .medium))
                    .foregroundStyle(Palette.textProduct)
                HStack(spacing: 6) {
                    Text(Money.rub(row.price))
                        .font(.pVariantPrice)
                        .foregroundStyle(Palette.variantPrice)
                    if let minimum = row.minQty, minimum > 1 {
                        Text("мин. \(minimum)")
                            .font(.pPriceHint)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            Spacer(minLength: 8)
            if qty > 0 {
                QtyStepper(
                    value: qty,
                    minimum: max(row.minQty ?? 1, 1),
                    removesAtMinimum: true,
                    compact: true,
                    onChange: onChange,
                    onRemove: { onChange(0) }
                )
            } else {
                Button {
                    Haptics.play(.selection)
                    onChange(max(row.minQty ?? 1, 1))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Palette.accentTint10))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(Text("Добавить \(row.name)"))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Шкала промо: «Закажите ещё на X ₽ — выезд бесплатно».
private struct RewardProgressView: View {
    let progress: Double
    let reward: Reward
    let menuSum: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let left = max((reward.goal ?? 0) - menuSum, 0)
            Text(left > 0
                 ? String(localized: "Ещё \(Money.rub(left)) — \(reward.label ?? String(localized: "бонус"))")
                 : (reward.label ?? String(localized: "Бонус получен")))
                .font(BrandFont.inter(13, .semibold))
                .foregroundStyle(left > 0 ? Palette.textProduct : Palette.success)
                .contentTransition(.numericText())
            ProgressView(value: progress)
                .tint(left > 0 ? Palette.accent : Palette.success)
                .animation(.snappy, value: progress)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
    }
}

// MARK: - «Также подходит»

/// Карточки допов с группами-пилюлями; добавление — доп к текущей позиции, не отдельный товар.
struct AlsoFitsSection: View {
    let viewModel: ConfiguratorViewModel
    @State private var group = AlsoFitsSection.all

    static let all = "__all__"

    var body: some View {
        let groups = [Self.all] + viewModel.configurator.alsoFitsGroups
        VStack(alignment: .leading, spacing: 14) {
            Text("Также подходит")
                .font(.pSection)
                .tracking(-0.6)
                .foregroundStyle(Palette.textProduct)
                .padding(.horizontal, Spacing.gutterProduct)
                .accessibilityAddTraits(.isHeader)
            PillSegment(items: groups, title: { $0 == Self.all ? String(localized: "Все") : $0 }, selection: $group)
                .padding(.horizontal, Spacing.gutterProduct)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(viewModel.configurator.alsoFits(group: group == Self.all ? nil : group)) { extra in
                        AlsoFitsCard(extra: extra, isOn: viewModel.isSelected(extra: extra.id)) {
                            viewModel.toggleExtra(extra.id)
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Spacing.gutterProduct)
            }
            .scrollTargetBehavior(.viewAligned)
        }
        .padding(.vertical, 24)
        .background(Palette.surfaceMuted)
    }
}

private struct AlsoFitsCard: View {
    let extra: Extra
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: extra.image?.resolvedURL, contentMode: .fit, maxPixel: 400, placeholder: Palette.surface)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            Text(extra.name)
                .font(BrandFont.inter(13, .semibold))
                .foregroundStyle(Palette.textProduct)
                .lineLimit(2)
                .frame(height: 34, alignment: .top)
            Text(extra.from == true ? String(localized: "от \(Money.rub(extra.price))") : Money.rub(extra.price))
                .font(.pVariantPrice)
                .foregroundStyle(Palette.variantPrice)
            Button(action: action) {
                Label {
                    Text(isOn ? "Добавлено" : "Добавить")
                } icon: {
                    Image(systemName: isOn ? "checkmark" : "plus")
                }
                .font(BrandFont.inter(13, .semibold))
                .foregroundStyle(isOn ? Palette.onAccent : Palette.accent)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(isOn ? Palette.accent : Palette.accentTint10))
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(10)
        .frame(width: 160)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surface))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
