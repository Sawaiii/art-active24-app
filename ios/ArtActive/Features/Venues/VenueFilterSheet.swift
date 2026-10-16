import SwiftUI

/// Фильтры площадок: тип события, тип площадки, метро, удобства (по группам),
/// диапазоны цены/вместимости/площади, поиск по опциям и счётчики.
struct VenueFilterSheet: View {
    let filters: VenueFiltersPayload?
    let counts: [String: [String: Int]]
    let onApply: (VenueQuery) -> Void

    @State private var draft: VenueQuery
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    init(query: VenueQuery, filters: VenueFiltersPayload?, counts: [String: [String: Int]], onApply: @escaping (VenueQuery) -> Void) {
        self.filters = filters
        self.counts = counts
        self.onApply = onApply
        _draft = State(initialValue: query)
    }

    var body: some View {
        NavigationStack {
            Form {
                if filters == nil {
                    Section { ListSkeleton(rows: 4) }
                }
                optionSection(String(localized: "Тип мероприятия"), options: filters?.events, selection: \.events, countKey: "events")
                optionSection(String(localized: "Тип площадки"), options: filters?.types, selection: \.types, countKey: "cats")
                rangeSection(String(localized: "Цена, ₽ / час"), key: "price", from: \.priceFrom, to: \.priceTo)
                rangeSection(String(localized: "Вместимость, чел."), key: "capacity", from: \.capacityFrom, to: \.capacityTo)
                rangeSection(String(localized: "Площадь, м²"), key: "area", from: \.areaFrom, to: \.areaTo)
                optionSection(String(localized: "Метро"), options: filters?.metro, selection: \.metro, countKey: "metro")
                ForEach(propGroups, id: \.self) { group in
                    optionSection(group.isEmpty ? String(localized: "Удобства") : group,
                                  options: filters?.props?.filter { ($0.group ?? "") == group },
                                  selection: \.props,
                                  countKey: "props")
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Поиск по фильтрам"))
            .navigationTitle(Text("Фильтры"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") {
                        Haptics.play(.selection)
                        draft = draft.cleared()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Применить") {
                        Haptics.play(.selection)
                        onApply(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("venuefilter.apply")
                }
            }
        }
    }

    private var propGroups: [String] {
        var groups: [String] = []
        for option in filters?.props ?? [] {
            let group = option.group ?? ""
            if !groups.contains(group) { groups.append(group) }
        }
        return groups
    }

    @ViewBuilder
    private func optionSection(_ title: String, options: [FilterOption]?, selection: WritableKeyPath<VenueQuery, Set<Int>>, countKey: String) -> some View {
        let visible = (options ?? []).filter { option in
            search.isEmpty || (option.name ?? "").localizedCaseInsensitiveContains(search)
        }
        if !visible.isEmpty {
            Section {
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(visible, id: \.self) { option in
                        if let id = option.id {
                            let isOn = draft[keyPath: selection].contains(id)
                            let count = counts[countKey]?[String(id)] ?? option.count
                            ToggleChip(
                                title: option.name ?? "",
                                subtitle: count.map { String($0) },
                                colorDot: countKey == "metro" ? Color(hexString: option.color) : nil,
                                isOn: isOn
                            ) {
                                if isOn { draft[keyPath: selection].remove(id) } else { draft[keyPath: selection].insert(id) }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func rangeSection(_ title: String, key: String, from: WritableKeyPath<VenueQuery, Int?>, to: WritableKeyPath<VenueQuery, Int?>) -> some View {
        if search.isEmpty, let range = filters?.ranges?[key], let minValue = range.min, let maxValue = range.max, maxValue > minValue {
            let bounds = Double(minValue)...Double(maxValue)
            Section {
                HStack {
                    Text(Money.digits(draft[keyPath: from] ?? minValue))
                    Spacer()
                    Text(Money.digits(draft[keyPath: to] ?? maxValue))
                }
                .font(.aaBlockTitle)
                .monospacedDigit()
                RangeSlider(
                    lower: Binding(
                        get: { Double(draft[keyPath: from] ?? minValue) },
                        set: { draft[keyPath: from] = Int($0) > minValue ? Int($0) : nil }
                    ),
                    upper: Binding(
                        get: { Double(draft[keyPath: to] ?? maxValue) },
                        set: { draft[keyPath: to] = Int($0) < maxValue ? Int($0) : nil }
                    ),
                    bounds: bounds,
                    step: max(1, Double((maxValue - minValue) / 100))
                )
                .padding(.vertical, 8)
            } header: {
                Text(title)
            }
        }
    }
}
