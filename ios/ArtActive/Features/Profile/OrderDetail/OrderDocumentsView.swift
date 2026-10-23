import SwiftUI

/// Раздел «Документы»: договор, акты, счета, КП — из CRM, Вызов Чата и от менеджера.
/// Файл открывается в QuickLook (скачивается во временную папку), страница — в Safari View.
struct OrderDocumentsSections: View {
    let state: ViewState<[OrderDocument]>
    let onPreview: (URL) -> Void
    let retry: () async -> Void

    @Environment(Router.self) private var router
    @State private var loadingId: String?
    @State private var openError: String?

    init(state: ViewState<[OrderDocument]>, onPreview: @escaping (URL) -> Void, retry: @escaping () async -> Void) {
        self.state = state
        self.onPreview = onPreview
        self.retry = retry
    }

    var body: some View {
        switch state {
        case .loading:
            Section {
                ListSkeleton(rows: 3)
                    .padding(.vertical, 8)
            }
        case let .error(message):
            Section {
                ErrorStateView(message: message, retry: retry)
            }
        case .empty:
            Section {
                EmptyStateView(
                    systemImage: "doc.text",
                    title: String(localized: "Документов пока нет"),
                    message: String(localized: "Договор, счета и акты появятся здесь после подтверждения заказа.")
                )
            }
        case let .content(documents):
            Section {
                ForEach(documents) { document in
                    row(document)
                }
            } footer: {
                if let openError {
                    Label(openError, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.error)
                } else {
                    Text("Нажмите, чтобы открыть; удерживайте — чтобы поделиться.")
                }
            }
        }
    }

    private func row(_ document: OrderDocument) -> some View {
        Button {
            Task { await open(document) }
        } label: {
            DocumentRow(document: document, isLoading: loadingId == document.id)
        }
        .buttonStyle(.plain)
        .disabled(loadingId != nil)
        .contextMenu {
            Button {
                Task { await open(document) }
            } label: {
                Label("Открыть", systemImage: "doc.text.magnifyingglass")
            }
            // Демо-документы рисуются на телефоне — их ссылкой не поделиться (делимся из QuickLook).
            if let url = URL(string: document.url), SafariView.canOpen(url), url.host != DemoBackend.baseURL.host {
                ShareLink(item: url) {
                    Label("Поделиться", systemImage: "square.and.arrow.up")
                }
            }
        }
        .accessibilityHint(Text("Открыть документ"))
        .accessibilityIdentifier("orderDetail.document.\(document.id)")
    }

    private func open(_ document: OrderDocument) async {
        openError = nil
        guard DocumentLoader.prefersQuickLook(document) else {
            openInBrowser(document)
            return
        }
        loadingId = document.id
        defer { loadingId = nil }
        do {
            let file = try await DocumentLoader.localFile(for: document)
            Haptics.play(.selection)
            onPreview(file)
        } catch {
            guard !error.isCancellation else { return }
            // Не скачалось (нужен вход в CRM, не тот тип) — пробуем открыть страницей.
            if let url = URL(string: document.url), SafariView.canOpen(url), url.host != DemoBackend.baseURL.host {
                router.openWeb(url)
            } else {
                openError = error.userMessage
                Haptics.play(.error)
            }
        }
    }

    private func openInBrowser(_ document: OrderDocument) {
        guard let url = URL(string: document.url) else {
            openError = String(localized: "Ссылка на документ повреждена")
            return
        }
        router.openWeb(url)
    }
}

/// Строка документа: иконка по типу, название, «тип · источник · дата · размер».
private struct DocumentRow: View {
    let document: OrderDocument
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: document.kind.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.accentTint08))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(BrandFont.golos(15, .medium, relativeTo: .subheadline))
                    .foregroundStyle(Palette.textProduct)
                    .lineLimit(2)
                Text(verbatim: subtitle)
                    .font(.aaCaption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if isLoading {
                ProgressView()
                    .tint(Palette.accent)
                    .accessibilityLabel(Text("Загрузка"))
            } else {
                Image(systemName: DocumentLoader.prefersQuickLook(document) ? "eye" : "arrow.up.forward.square")
                    .foregroundStyle(Palette.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [document.kind.title, document.source.title]
        if let day = DateText.day(fromAPI: document.date) { parts.append(day) }
        if let size = document.size, size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}
