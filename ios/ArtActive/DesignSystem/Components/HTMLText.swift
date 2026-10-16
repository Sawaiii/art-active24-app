import SwiftUI

/// Нативный рендер ограниченного HTML контракта (p, br, strong/b, em/i, ul, ol, li, a).
/// Без WebKit: собственный разбор в абзацы и пункты списков с AttributedString.
enum HTMLBlock: Hashable {
    case paragraph(AttributedString)
    case listItem(marker: String, text: AttributedString)
}

enum HTMLParser {
    static func parse(_ html: String) -> [HTMLBlock] {
        var blocks: [HTMLBlock] = []
        var current = AttributedString()
        var bold = 0
        var italic = 0
        var link: URL?
        var listStack: [(ordered: Bool, counter: Int)] = []
        var inListItem = false
        var marker = ""

        func flush() {
            let cleaned = HTMLParser.trimmed(current)
            if !cleaned.characters.isEmpty {
                if inListItem {
                    blocks.append(.listItem(marker: marker, text: cleaned))
                } else {
                    blocks.append(.paragraph(cleaned))
                }
            }
            current = AttributedString()
        }

        func appendText(_ raw: String) {
            let text = decodeEntities(collapseWhitespace(raw))
            guard !text.isEmpty else { return }
            var piece = AttributedString(text)
            var intent: InlinePresentationIntent = []
            if bold > 0 { intent.insert(.stronglyEmphasized) }
            if italic > 0 { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if let link {
                piece.link = link
            }
            current.append(piece)
        }

        func handleTag(_ raw: String) {
            let isClosing = raw.hasPrefix("/")
            let body = isClosing ? String(raw.dropFirst()) : raw
            let name = body.split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "\n" }).first.map { $0.lowercased() } ?? ""
            switch (name, isClosing) {
            case ("p", false), ("div", false), ("h1", false), ("h2", false), ("h3", false), ("h4", false):
                flush()
            case ("p", true), ("div", true):
                flush()
            case ("h1", true), ("h2", true), ("h3", true), ("h4", true):
                flush()
            case ("br", _):
                current.append(AttributedString("\n"))
            case ("strong", false), ("b", false):
                bold += 1
            case ("strong", true), ("b", true):
                bold = max(bold - 1, 0)
            case ("em", false), ("i", false):
                italic += 1
            case ("em", true), ("i", true):
                italic = max(italic - 1, 0)
            case ("a", false):
                link = attribute("href", in: body).flatMap { $0.resolvedURL }
            case ("a", true):
                link = nil
            case ("ul", false):
                flush(); listStack.append((false, 0))
            case ("ol", false):
                flush(); listStack.append((true, 0))
            case ("ul", true), ("ol", true):
                flush(); inListItem = false
                if !listStack.isEmpty { listStack.removeLast() }
            case ("li", false):
                flush()
                inListItem = true
                if var top = listStack.popLast() {
                    top.counter += 1
                    marker = top.ordered ? "\(top.counter)." : "•"
                    listStack.append(top)
                } else {
                    marker = "•"
                }
            case ("li", true):
                flush()
                inListItem = false
            default:
                break
            }
        }

        var index = html.startIndex
        while index < html.endIndex {
            if html[index] == "<", let close = html[index...].firstIndex(of: ">") {
                let tagBody = html[html.index(after: index)..<close]
                handleTag(String(tagBody))
                index = html.index(after: close)
            } else {
                let next = html[index...].firstIndex(of: "<") ?? html.endIndex
                appendText(String(html[index..<next]))
                index = next
            }
        }
        flush()
        return blocks
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: "\(name)=") else { return nil }
        var rest = tag[range.upperBound...]
        guard let quote = rest.first else { return nil }
        if quote == "\"" || quote == "'" {
            rest = rest.dropFirst()
            guard let end = rest.firstIndex(of: quote) else { return nil }
            return decodeEntities(String(rest[..<end]))
        }
        let end = rest.firstIndex(where: { $0 == " " || $0 == ">" }) ?? rest.endIndex
        return String(rest[..<end])
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        var lastWasSpace = false
        for char in text {
            if char.isWhitespace {
                if !lastWasSpace { out.append(" ") }
                lastWasSpace = true
            } else {
                out.append(char)
                lastWasSpace = false
            }
        }
        return out
    }

    private static func trimmed(_ text: AttributedString) -> AttributedString {
        var result = text
        while let first = result.characters.first, first == " " || first == "\n" {
            result.removeSubrange(result.startIndex..<result.characters.index(after: result.startIndex))
        }
        while let last = result.characters.last, last == " " || last == "\n" {
            let lastIndex = result.characters.index(before: result.endIndex)
            result.removeSubrange(lastIndex..<result.endIndex)
        }
        return result
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = [
            "&nbsp;": "\u{00A0}", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
            "&apos;": "'", "&laquo;": "«", "&raquo;": "»", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
            "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”", "&bull;": "•", "&times;": "×",
            "&deg;": "°", "&laquo": "«", "&raquo": "»",
        ]
        var result = text
        for (entity, value) in named { result = result.replacingOccurrences(of: entity, with: value) }
        // Числовые &#NNN; и &#xHH;
        while let start = result.range(of: "&#"), let end = result[start.upperBound...].firstIndex(of: ";") {
            let code = result[start.upperBound..<end]
            let scalarValue: UInt32? = code.hasPrefix("x") || code.hasPrefix("X")
                ? UInt32(code.dropFirst(), radix: 16)
                : UInt32(code)
            let replacement = scalarValue.flatMap { Unicode.Scalar($0) }.map { String(Character($0)) } ?? ""
            result.replaceSubrange(start.lowerBound...end, with: replacement)
        }
        return result
    }

    /// Плоский текст без разметки (для превью, VoiceOver).
    static func plainText(_ html: String) -> String {
        parse(html).map { block -> String in
            switch block {
            case let .paragraph(text): return String(text.characters)
            case let .listItem(marker, text): return "\(marker) \(String(text.characters))"
            }
        }.joined(separator: "\n")
    }
}

/// Отображение HTML-блоков; при `collapsedHeight` — свёрнуто с «Показать ещё».
struct HTMLText: View {
    let html: String
    var font: Font = .pBody
    var color: Color = Palette.textProduct
    var collapsedHeight: CGFloat?
    /// Цвет фона под текстом — для градиента сворачивания.
    var fadeColor: Color = Palette.page

    @State private var expanded = false
    @State private var blocks: [HTMLBlock] = []
    @State private var fullHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
                .frame(maxHeight: isCollapsed ? collapsedHeight : nil, alignment: .top)
                .clipped()
                .overlay(alignment: .bottom) {
                    if isCollapsed {
                        LinearGradient(colors: [fadeColor.opacity(0), fadeColor], startPoint: .top, endPoint: .bottom)
                            .frame(height: 48)
                            .allowsHitTesting(false)
                    }
                }
            if let collapsedHeight, fullHeight > collapsedHeight + 8 {
                Button {
                    Haptics.play(.selection)
                    withAnimation(Motion.slow(reduceMotion)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Свернуть" : "Показать ещё")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                }
                .buttonStyle(LinkButtonStyle(font: .pBody))
            }
        }
        .task(id: html) { blocks = HTMLParser.parse(html) }
    }

    private var isCollapsed: Bool {
        guard let collapsedHeight else { return false }
        return !expanded && fullHeight > collapsedHeight + 8
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .paragraph(text):
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                case let .listItem(marker, text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).font(font).foregroundStyle(Palette.accent)
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(Palette.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightKey.self) { fullHeight = max(fullHeight, $0) }
    }

    private struct HeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
}
