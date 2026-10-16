import SwiftUI

/// Степпер количества: серая капсула h34, кнопки 30, значение 16 bold.
struct QtyStepper: View {
    let value: Int
    var minimum: Int = 1
    var maximum: Int = Configurator.maxQty
    var unit: String?
    /// На минимуме «−» удаляет позицию (липкий бар, корзина).
    var removesAtMinimum = false
    var compact = false
    let onChange: (Int) -> Void
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            stepButton(systemName: removesAtMinimum && value <= minimum ? "trash" : "minus", label: "Уменьшить") {
                if value <= minimum {
                    if removesAtMinimum, let onRemove {
                        Haptics.play(.swipeThreshold)
                        onRemove()
                    } else {
                        Haptics.play(.limit)
                    }
                } else {
                    Haptics.play(.step)
                    onChange(value - 1)
                }
            }
            Text(unit.map { "\(value) \($0)" } ?? "\(value)")
                .font(BrandFont.golos(compact ? 15 : 16, .bold, relativeTo: .body))
                .foregroundStyle(Palette.textStrong)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .frame(minWidth: compact ? 28 : 36)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            stepButton(systemName: "plus", label: "Увеличить") {
                if value >= maximum {
                    Haptics.play(.limit)
                } else {
                    Haptics.play(.step)
                    onChange(value + 1)
                }
            }
        }
        .padding(.horizontal, 2)
        .frame(height: compact ? 34 : 40)
        .background(Capsule().fill(Palette.surfaceMuted))
        .animation(.snappy(duration: 0.2), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Количество"))
        .accessibilityValue(Text("\(value)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where value < maximum: onChange(value + 1)
            case .decrement where value > minimum: onChange(value - 1)
            default: break
            }
        }
    }

    private func stepButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.textStrong)
                .frame(width: compact ? 30 : 36, height: compact ? 30 : 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(scale: 0.85))
        .accessibilityLabel(Text(label))
    }
}

/// Сегмент срока аренды: подложка #F5F5F7 r12 p3, выбранный — белый с тенью.
struct TimeSegmentControl: View {
    let options: [TimeOption]
    let selected: TimeSelection?
    let onSelect: (TimeOption) -> Void

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(options) { option in
                    let isActive = isSelected(option)
                    Button {
                        onSelect(option)
                    } label: {
                        HStack(spacing: 4) {
                            if case .more = option {
                                Image(systemName: "calendar")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Text(title(option))
                                .font(isActive ? .pSegmentActive : .pSegment)
                                .lineLimit(1)
                        }
                        .foregroundStyle(isActive ? Palette.accent : Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minWidth: 44)
                        .background {
                            if isActive {
                                RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
                                    .fill(Palette.surface)
                                    .brandShadow(.segmentActive)
                                    .matchedGeometryEffect(id: "time", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(3)
            .animation(Motion.snappy(reduceMotion), value: selected)
        }
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceMuted))
    }

    private func isSelected(_ option: TimeOption) -> Bool {
        switch option {
        case let .value(value):
            return value == selected
        case .more:
            guard let selected else { return false }
            let listed = options.contains { if case let .value(v) = $0 { return v == selected } else { return false } }
            return !listed
        }
    }

    private func title(_ option: TimeOption) -> String {
        if case .more = option, isSelected(option), let selected {
            return TimeOption.value(selected).shortTitle
        }
        return option.shortTitle
    }
}

/// Переключатель «Доставка / Самовывоз», «Аренда / Купить».
struct BrandToggle<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.self) { item in
                let isActive = item == selection
                Button {
                    guard !isActive else { return }
                    Haptics.play(.selection)
                    withAnimation(Motion.snappy(reduceMotion)) { selection = item }
                } label: {
                    Text(title(item))
                        .font(isActive ? BrandFont.golos(15, .semibold) : BrandFont.golos(15))
                        .foregroundStyle(isActive ? Palette.textProduct : Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if isActive {
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(Palette.surface)
                                    .brandShadow(.toggleActive)
                                    .matchedGeometryEffect(id: "toggle", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: Radius.input, style: .continuous).fill(Palette.surfaceMuted))
    }
}

/// Двойной ползунок диапазона (цена, вместимость, площадь).
struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let bounds: ClosedRange<Double>
    var step: Double = 1

    private let thumb: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - thumb, 1)
            let span = max(bounds.upperBound - bounds.lowerBound, 1)
            let lowX = CGFloat((lower - bounds.lowerBound) / span) * width
            let highX = CGFloat((upper - bounds.lowerBound) / span) * width

            ZStack(alignment: .leading) {
                Capsule().fill(Palette.bgTertiary).frame(height: 4).padding(.horizontal, thumb / 2)
                Capsule().fill(Palette.accent)
                    .frame(width: max(highX - lowX, 0), height: 4)
                    .offset(x: lowX + thumb / 2)
                handle
                    .offset(x: lowX)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("range")).onChanged { value in
                        let raw = bounds.lowerBound + Double(min(max(value.location.x - thumb / 2, 0), width) / width) * span
                        let snapped = (raw / step).rounded() * step
                        let clamped = min(max(snapped, bounds.lowerBound), upper)
                        if clamped != lower { lower = clamped; Haptics.play(.step) }
                    })
                    .accessibilityLabel(Text("Минимум"))
                    .accessibilityValue(Text(Money.digits(Int(lower))))
                    .accessibilityAdjustableAction { direction in
                        let delta = direction == .increment ? step : -step
                        lower = min(max(lower + delta, bounds.lowerBound), upper)
                    }
                handle
                    .offset(x: highX)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("range")).onChanged { value in
                        let raw = bounds.lowerBound + Double(min(max(value.location.x - thumb / 2, 0), width) / width) * span
                        let snapped = (raw / step).rounded() * step
                        let clamped = max(min(snapped, bounds.upperBound), lower)
                        if clamped != upper { upper = clamped; Haptics.play(.step) }
                    })
                    .accessibilityLabel(Text("Максимум"))
                    .accessibilityValue(Text(Money.digits(Int(upper))))
                    .accessibilityAdjustableAction { direction in
                        let delta = direction == .increment ? step : -step
                        upper = max(min(upper + delta, bounds.upperBound), lower)
                    }
            }
            .frame(height: thumb)
            .coordinateSpace(.named("range"))
        }
        .frame(height: thumb)
    }

    private var handle: some View {
        Circle()
            .fill(Palette.surface)
            .frame(width: thumb, height: thumb)
            .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2))
            .brandShadow(.segmentActive)
            .contentShape(Circle().inset(by: -10))
    }
}
