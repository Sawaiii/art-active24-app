import SwiftUI
import UIKit

/// Поле телефона на UITextField: маска «+7 (999) 999-99-99» с корректной позицией курсора,
/// textContentType `.telephoneNumber`, клавиатура phonePad.
struct PhoneTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var autoFocus = false
    var onSubmit: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .phonePad
        field.textContentType = .telephoneNumber
        field.font = BrandFont.uiFont(.golos, .regular, size: 17, style: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(Palette.textStrong)
        field.tintColor = UIColor(Palette.accent)
        field.placeholder = placeholder
        field.text = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if autoFocus {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PhoneTextField
        init(parent: PhoneTextField) { self.parent = parent }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = (field.text ?? "") as NSString
            let start = Self.nationalDigitCount(in: current.substring(to: range.location), full: current as String)
            let inRange = Self.nationalDigitCount(in: current.substring(to: range.location + range.length), full: current as String) - start

            var digits = Array(PhoneFormatter.nationalDigits(from: current as String))
            let inserted = Array(string.count > 1 ? PhoneFormatter.nationalDigits(from: string) : string.filter { $0.isASCII && $0.isNumber })

            var cursor: Int
            if string.isEmpty, inRange == 0, range.length > 0 {
                // Стёрли разделитель маски — стираем цифру перед ним.
                guard start > 0 else { return false }
                digits.remove(at: start - 1)
                cursor = start - 1
            } else {
                let lower = min(start, digits.count)
                let upper = min(start + inRange, digits.count)
                digits.replaceSubrange(lower..<upper, with: inserted)
                cursor = lower + inserted.count
            }
            digits = Array(digits.prefix(PhoneFormatter.digitsCount))
            cursor = min(cursor, digits.count)

            let masked = digits.isEmpty ? "" : PhoneFormatter.masked("+7" + String(digits))
            field.text = masked
            parent.text = masked
            Self.placeCursor(in: field, afterDigits: cursor)
            return false
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            return true
        }

        /// Значащие цифры в начале маскированной строки («7» из «+7» не считается).
        private static func nationalDigitCount(in prefix: String, full: String) -> Int {
            let count = prefix.filter { $0.isASCII && $0.isNumber }.count
            return full.hasPrefix("+7") && prefix.count >= 2 ? max(count - 1, 0) : count
        }

        private static func placeCursor(in field: UITextField, afterDigits count: Int) {
            let text = field.text ?? ""
            var offset = text.utf16.count
            if count == 0 {
                offset = min(4, text.utf16.count)
            } else {
                var digits = 0
                var utf16Offset = 0
                for (index, char) in text.enumerated() {
                    utf16Offset += String(char).utf16.count
                    guard char.isASCII, char.isNumber, index > 1 else { continue }
                    digits += 1
                    if digits == count { offset = utf16Offset; break }
                }
            }
            if let position = field.position(from: field.beginningOfDocument, offset: offset) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
        }
    }
}

/// Скрытый UITextField для кода из SMS: `.oneTimeCode` (автоподстановка из уведомления),
/// цифровая клавиатура, ограничение длины. Визуально ячейки рисует SwiftUI.
struct OneTimeCodeTextField: UIViewRepresentable {
    @Binding var code: String
    let length: Int
    var isFocused = true

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .numberPad
        field.textContentType = .oneTimeCode
        field.textColor = .clear
        field.tintColor = .clear
        field.backgroundColor = .clear
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.accessibilityLabel = String(localized: "Код из SMS")
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != code { field.text = code }
        if isFocused, !field.isFirstResponder, field.window != nil {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: OneTimeCodeTextField
        init(parent: OneTimeCodeTextField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            let digits = String((field.text ?? "").filter { $0.isASCII && $0.isNumber }.prefix(parent.length))
            if field.text != digits { field.text = digits }
            if parent.code != digits { parent.code = digits }
        }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            string.isEmpty || string.allSatisfy { $0.isNumber } || string.count > 1
        }
    }
}
