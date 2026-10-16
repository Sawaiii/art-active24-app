import SwiftUI

/// Фильтр листинга: ползунок цены (диапазон из фасетов) и цвета. Шит с detents.
struct FilterSheet: View {
    let facets: ProductFacets?
    let onApply: (ProductQuery) -> Void

    @State private var draft: ProductQuery
    @State private var lower: Double
    @State private var upper: Double
    @Environment(\.dismiss) private var dismiss

    init(query: ProductQuery, facets: ProductFacets?, onApply: @escaping (ProductQuery) -> Void) {
        self.facets = facets
        self.onApply = onApply
        _draft = State(initialValue: query)
        let bounds = FilterSheet.bounds(facets)
        _lower = State(initialValue: Double(query.priceMin ?? Int(bounds.lowerBound)))
        _upper = State(initialValue: Double(query.priceMax ?? Int(bounds.upperBound)))
    }

    private static func bounds(_ facets: ProductFacets?) -> ClosedRange<Double> {
        let minValue = Double(facets?.priceMin ?? 0)
        let maxValue = Double(max(facets?.priceMax ?? 100_000, (facets?.priceMin ?? 0) + 1))
        return minValue...maxValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        priceField(value: lower, label: String(localized: "от"))
                        Spacer()
                        priceField(value: upper, label: String(localized: "до"))
                    }
                    RangeSlider(lower: $lower, upper: $upper, bounds: Self.bounds(facets), step: priceStep)
                        .padding(.vertical, 8)
                } header: {
                    Text("Цена")
                }

                if let colors = facets?.colors, !colors.isEmpty {
                    Section {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(colors, id: \.self) { color in
                                let name = color.name ?? ""
                                ToggleChip(
                                    title: name,
                                    subtitle: color.count.map { String($0) },
                                    colorDot: Color(hexString: color.hex),
                                    isOn: draft.colors.contains(name)
                                ) {
                                    if draft.colors.contains(name) { draft.colors.remove(name) } else { draft.colors.insert(name) }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Цвет")
                    }
                }
            }
            .navigationTitle(Text("Фильтры"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") {
                        Haptics.play(.selection)
                        let bounds = Self.bounds(facets)
                        lower = bounds.lowerBound
                        upper = bounds.upperBound
                        draft.colors = []
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") { apply() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("filter.apply")
                }
            }
        }
    }

    private var priceStep: Double {
        let span = Self.bounds(facets).upperBound - Self.bounds(facets).lowerBound
        return span > 100_000 ? 1000 : (span > 10_000 ? 100 : 10)
    }

    private func priceField(value: Double, label: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.aaCaption).foregroundStyle(Palette.textSecondary)
            Text(Money.rub(Int(value)))
                .font(.aaBlockTitle)
                .foregroundStyle(Palette.textProduct)
                .contentTransition(.numericText(value: value))
                .monospacedDigit()
        }
    }

    private func apply() {
        let bounds = Self.bounds(facets)
        var query = draft
        query.priceMin = lower > bounds.lowerBound ? Int(lower) : nil
        query.priceMax = upper < bounds.upperBound ? Int(upper) : nil
        Haptics.play(.selection)
        onApply(query)
        dismiss()
    }
}
