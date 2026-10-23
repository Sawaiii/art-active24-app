import SwiftUI

/// Пояснения и мелкие подсказки: минимум 12 pt (HIG: не мельче 11), масштабируются вместе с caption.
extension Font {
    static let configHint = BrandFont.inter(12, .regular, relativeTo: .caption)
}

/// Русские формы числительных для подписей, которые не покрыты каталогом строк.
enum RuPlural {
    static func form(_ n: Int, one: String, few: String, many: String) -> String {
        let mod100 = abs(n) % 100
        let mod10 = abs(n) % 10
        if mod100 >= 11, mod100 <= 14 { return many }
        switch mod10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    static func days(_ n: Int) -> String {
        "\(n) " + form(n, one: "день", few: "дня", many: "дней")
    }

    static func venues(_ n: Int) -> String {
        "\(n) " + form(n, one: "площадка", few: "площадки", many: "площадок")
    }
}

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
                }
                // Отступы — полями прокрутки: первая карточка не обрезается, снап по карточкам.
                .contentMargins(.horizontal, Spacing.gutterProduct, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .padding(.horizontal, -Spacing.gutterProduct)
                .onAppear {
                    // Выбранный комплект (например, из корзины) — целиком в зоне видимости.
                    guard let id = viewModel.state?.complectId, id != complects.first?.id else { return }
                    proxy.scrollTo(id)
                }
                .onChange(of: viewModel.state?.complectId) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy) { proxy.scrollTo(id) }
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
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        // 44 pt зона нажатия при компактной визуальной ссылке.
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(LinkButtonStyle(font: BrandFont.inter(14, .medium, relativeTo: .subheadline)))
                    .accessibilityIdentifier("config.complects.all")
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

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                if let image = complect.image?.resolvedURL {
                    // Фото комплекта 800×600 — 4:3, без растяжения.
                    AspectImage(url: image, aspect: MediaAspect.photo, cornerRadius: Radius.sm, maxPixel: 200, placeholder: Palette.surface)
                        .frame(width: 56)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(complect.title)
                        .font(.pVariantTitle)
                        .foregroundStyle(Palette.textProduct)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    if complect.side(priceType) != nil {
                        Text(ComplectPrice.text(complect, priceType: priceType))
                            .font(.pVariantPrice)
                            .foregroundStyle(Palette.variantPrice)
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    } else if let subtitle = complect.subtitle {
                        Text(subtitle)
                            .font(.pVariantPrice)
                            .foregroundStyle(Palette.variantPrice)
                            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
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
        .accessibilityIdentifier("config.complect.\(complect.id)")
        .overlay(alignment: .topTrailing) {
            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? Palette.accent : Palette.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(isSelected ? Palette.accentTint10 : Palette.surfaceMuted))
                        .padding(6)
                        // Визуально 20 pt, зона нажатия 44×44 (HIG).
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Подробнее о комплекте"))
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

enum ComplectPrice {
    /// Цена комплекта для карточки. Комплект-формат с нулевой ценой и вариантами
    /// (плов: «Привозим готовое») — «от {минимальная цена варианта} ₽ {постфикс}».
    static func text(_ complect: Complect, priceType: PriceType) -> String {
        guard let side = complect.side(priceType) else { return "" }
        if side.amount == 0, side.onRequest != true,
           let cheapest = complect.subList
               .compactMap({ $0.side(priceType) })
               .filter({ $0.amount > 0 })
               .min(by: { $0.amount < $1.amount }) {
            let tag = PriceTag(amount: cheapest.amount, from: true, unit: cheapest.postfix ?? side.postfix, onRequest: nil)
            return Money.tag(tag)
        }
        return text(side)
    }

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
                        AspectImage(url: complect.image?.resolvedURL, aspect: MediaAspect.photo, cornerRadius: Radius.sm, maxPixel: 240)
                            .frame(width: 84)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(complect.title)
                                .font(BrandFont.inter(15, .semibold, relativeTo: .subheadline))
                                .foregroundStyle(Palette.textProduct)
                            if complect.side(viewModel.state?.priceType ?? .rent) != nil {
                                Text(ComplectPrice.text(complect, priceType: viewModel.state?.priceType ?? .rent))
                                    .font(BrandFont.inter(14, .medium, relativeTo: .footnote))
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
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(complect.id == viewModel.state?.complectId ? .isSelected : [])
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let image = complect.image?.resolvedURL {
                        AspectImage(url: image, aspect: MediaAspect.photo, contentMode: .fit, cornerRadius: Radius.md, maxPixel: 900, placeholder: Palette.page)
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
            .toolbar {
                // Явный путь закрытия помимо свайпа (HIG: модальные экраны всегда закрываемы).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
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
                .font(BrandFont.inter(15, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Palette.textProduct)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: systemImage)
                        .font(BrandFont.inter(11, .bold, relativeTo: .caption2))
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
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
            .accessibilityIdentifier("config.priceType")
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
                            .font(BrandFont.inter(14, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Palette.textProduct)
                            .accessibilityAddTraits(.isHeader)
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
                    .font(BrandFont.inter(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.textProduct)
                if let side = sub.side(priceType), side.amount > 0 || side.onRequest == true {
                    Text(ComplectPrice.text(side))
                        .font(.pVariantPrice)
                        .foregroundStyle(Palette.variantPrice)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
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
        .accessibilityIdentifier("config.sub.\(sub.id)")
    }
}

/// Батут: способ установки — карточка с фото, текстом и фикс-надбавкой.
private struct InstallOptionCard: View {
    let sub: Sub
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // На крупных размерах шрифта фото уходит над текстом.
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        Button(action: action) {
            layout {
                if let image = sub.image?.resolvedURL {
                    AspectImage(url: image, aspect: MediaAspect.photo, cornerRadius: Radius.sm, maxPixel: 300)
                        .frame(width: stacked ? nil : 96)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(sub.name)
                            .font(BrandFont.inter(15, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Palette.textProduct)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(surchargeText)
                            .font(BrandFont.inter(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
                            .fixedSize()
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
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityIdentifier("config.sub.\(sub.id)")
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
                    .font(.configHint)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            .presentationDetents([.height(320), .large])
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
                    Text(verbatim: RuPlural.days(value)).tag(value)
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
                .font(.configHint)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// `.extra-btn`: фото, название, цена, обязательность; у счётных — свой степпер.
struct ExtraRow: View {
    let extra: Extra
    let viewModel: ConfiguratorViewModel

    var body: some View {
        let isOn = viewModel.isSelected(extra: extra.id)
        // У счётной опции внутри свой степпер — его нельзя схлопывать в один элемент VoiceOver.
        let hasStepper = extra.isCountable && isOn
        HStack(spacing: 12) {
            if let image = extra.image?.resolvedURL {
                AspectImage(url: image, aspect: MediaAspect.photo, cornerRadius: Radius.sm, maxPixel: 200)
                    .frame(width: 60)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(extra.name)
                        .font(BrandFont.inter(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Palette.textProduct)
                        .fixedSize(horizontal: false, vertical: true)
                    if extra.isRequired {
                        Text("обязательно")
                            .font(BrandFont.inter(11, .semibold, relativeTo: .caption2))
                            .fixedSize()
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
                        .font(.configHint)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if hasStepper {
                QtyStepper(
                    value: viewModel.extraQty(extra.id),
                    minimum: extra.isRequired ? 1 : 0,
                    removesAtMinimum: !extra.isRequired,
                    compact: true,
                    onChange: { viewModel.setExtraQty(extra.id, $0) },
                    onRemove: { viewModel.setExtraQty(extra.id, 0) }
                )
                .accessibilityLabel(Text("Количество, \(extra.name)"))
            } else {
                Image(systemName: isOn ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 24))
                    .foregroundStyle(isOn ? Palette.accent : Palette.disabled)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .frame(minHeight: 56)
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
            if !hasStepper { viewModel.toggleExtra(extra.id) }
        }
        .accessibilityElement(children: hasStepper ? .contain : .combine)
        .accessibilityAddTraits(hasStepper ? [] : .isButton)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("config.extra.\(extra.id)")
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
                            .font(BrandFont.inter(14, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Palette.textProduct)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(group.rows) { row in
                        MenuRowView(row: row, qty: viewModel.menuQty(row.id)) { viewModel.setMenuQty(row.id, $0) }
                    }
                }
            }
            if let error = viewModel.validationError {
                // Ошибка минимума: иконка + текст, не только цвет.
                Label {
                    Text(error.message)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
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

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(BrandFont.inter(14, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textProduct)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(Money.rub(row.price))
                        .font(.pVariantPrice)
                        .foregroundStyle(Palette.variantPrice)
                    if let minimum = row.minQty, minimum > 1 {
                        Text("мин. \(minimum)")
                            .font(.configHint)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            if qty > 0 {
                QtyStepper(
                    value: qty,
                    minimum: max(row.minQty ?? 1, 1),
                    removesAtMinimum: true,
                    compact: true,
                    onChange: onChange,
                    onRemove: { onChange(0) }
                )
                .accessibilityLabel(Text("Количество, \(row.name)"))
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
                        // Визуально 34 pt, зона нажатия 44×44 (HIG).
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .accessibilityLabel(Text("Добавить \(row.name)"))
            }
        }
    }
}

/// Шкала промо: «Закажите ещё на X ₽ — выезд бесплатно».
private struct RewardProgressView: View {
    let progress: Double
    let reward: Reward
    let menuSum: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let left = max((reward.goal ?? 0) - menuSum, 0)
            Text(left > 0
                 ? String(localized: "Ещё \(Money.rub(left)) — \(reward.label ?? String(localized: "бонус"))")
                 : (reward.label ?? String(localized: "Бонус получен")))
                .font(BrandFont.inter(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(left > 0 ? Palette.textProduct : Palette.success)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
            ProgressView(value: progress)
                .tint(left > 0 ? Palette.accent : Palette.success)
                .animation(Motion.snappy(reduceMotion), value: progress)
        }
        .accessibilityElement(children: .combine)
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

    /// Ширина карточки растёт с Dynamic Type, но не шире 280.
    @ScaledMetric(relativeTo: .body) private var cardWidth: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AspectImage(url: extra.image?.resolvedURL, aspect: MediaAspect.photo, cornerRadius: Radius.md, maxPixel: 400, placeholder: Palette.surface)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                // Две строки резервируются, а не фиксируются по высоте: кнопки выровнены, текст не обрезается.
                Text(extra.name)
                    .font(BrandFont.inter(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Palette.textProduct)
                    .lineLimit(2, reservesSpace: true)
                Text(extra.from == true ? String(localized: "от \(Money.rub(extra.price))") : Money.rub(extra.price))
                    .font(.pVariantPrice)
                    .foregroundStyle(Palette.variantPrice)
            }
            .accessibilityElement(children: .combine)
            Button(action: action) {
                Label {
                    Text(isOn ? "Добавлено" : "Добавить")
                } icon: {
                    Image(systemName: isOn ? "checkmark" : "plus")
                }
                .font(BrandFont.inter(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(isOn ? Palette.onAccent : Palette.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(isOn ? Palette.accent : Palette.accentTint10))
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(Text(isOn ? "Добавлено: \(extra.name)" : "Добавить \(extra.name)"))
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
        .padding(10)
        .frame(width: min(cardWidth, 280))
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.surface))
        .accessibilityElement(children: .contain)
    }
}
