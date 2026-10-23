import UIKit

/// Документы демо-заказа: маленький PDF рисуется на телефоне (офлайн), чтобы QuickLook и
/// «Поделиться» работали как с настоящими файлами CRM / Вызов Чата.
enum DemoDocumentPDF {
    /// A4 в пунктах.
    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    private static let accent = UIColor(hex: 0x705ABF)

    static func render(title: String, kind: DocumentKind, date: String?) -> Data? {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { context in
            context.beginPage()
            let margin: CGFloat = 56
            var y: CGFloat = margin

            draw("АРТ-АКТИВ", font: .systemFont(ofSize: 13, weight: .bold), color: accent, at: &y, margin: margin)
            draw("art-active24.ru · аренда для мероприятий", font: .systemFont(ofSize: 10), color: .gray, at: &y, margin: margin)
            y += 24
            draw(title, font: .systemFont(ofSize: 22, weight: .semibold), color: .black, at: &y, margin: margin)
            draw(kind.title + (date.map { " от \($0)" } ?? ""), font: .systemFont(ofSize: 12), color: .darkGray, at: &y, margin: margin)
            y += 20

            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y))
            line.addLine(to: CGPoint(x: page.width - margin, y: y))
            UIColor(white: 0.85, alpha: 1).setStroke()
            line.lineWidth = 1
            line.stroke()
            y += 20

            let body = """
            Демонстрационный документ. В рабочем приложении здесь открывается файл из CRM, \
            Вызов Чата или ссылка, которую приложил менеджер.

            Документ можно переслать через «Поделиться» — так же, как настоящий.
            """
            draw(body, font: .systemFont(ofSize: 12), color: .black, at: &y, margin: margin)
        }
    }

    private static func draw(_ text: String, font: UIFont, color: UIColor, at y: inout CGFloat, margin: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = page.width - margin * 2
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        (text as NSString).draw(
            with: CGRect(x: margin, y: y, width: width, height: ceil(rect.height)),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        y += ceil(rect.height) + 6
    }
}
