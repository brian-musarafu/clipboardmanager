import Foundation

/// Heuristics for recognising secrets that shouldn't sit in plain view.
///
/// Two mechanisms protect the user (see also `ClipboardMonitor`, which excludes
/// content that password managers explicitly mark as concealed):
/// - a Luhn-valid card number, or
/// - a US SSN-shaped string.
///
/// These are conservative on purpose — false positives only mean an item gets
/// redacted/encrypted, but we still avoid flagging ordinary text.
enum SensitiveContentDetector {
    static func isSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return isCardNumber(trimmed) || isSSN(trimmed)
    }

    /// A 13–19 digit number (allowing spaces/dashes) that passes the Luhn check.
    private static func isCardNumber(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        guard digits.count >= 13, digits.count <= 19 else { return false }
        // Reject if the original had other characters besides digits/spaces/dashes.
        let allowed = CharacterSet(charactersIn: "0123456789 -")
        guard text.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return luhnValid(digits)
    }

    private static func luhnValid(_ digits: String) -> Bool {
        var sum = 0
        for (offset, character) in digits.reversed().enumerated() {
            guard let value = character.wholeNumberValue else { return false }
            if offset.isMultiple(of: 2) {
                sum += value
            } else {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    /// `123-45-6789`.
    private static func isSSN(_ text: String) -> Bool {
        text.range(of: "^\\d{3}-\\d{2}-\\d{4}$", options: .regularExpression) != nil
    }
}
