import AppKit
import CoreImage

/// Pure content analysis for the Phase 4 "smart clipboard": recognises links,
/// emails, colors, and JSON in copied text, and generates QR codes. All methods
/// are side-effect free so they can be called freely from views.
enum SmartContentDetector {

    // MARK: - URL

    static func detectURL(_ raw: String) -> URL? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains(" "),
              let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    // MARK: - Email

    static func detectEmail(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.contains(where: \.isWhitespace) else { return nil }
        let pattern = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        guard s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return s
    }

    // MARK: - Color

    /// Recognises `#RGB`, `#RRGGBB`, `rgb(r,g,b)` and `rgba(r,g,b,a)`.
    static func detectColor(_ raw: String) -> NSColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return hexColor(s) ?? rgbColor(s)
    }

    private static func hexColor(_ input: String) -> NSColor? {
        var hex = input
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 3, hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&value) else { return nil }
        return NSColor(
            srgbRed: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }

    private static func rgbColor(_ input: String) -> NSColor? {
        let lower = input.lowercased().replacingOccurrences(of: " ", with: "")
        guard lower.hasPrefix("rgb(") || lower.hasPrefix("rgba("), lower.hasSuffix(")") else { return nil }
        let inner = lower.drop(while: { $0 != "(" }).dropFirst().dropLast()
        let parts = inner.split(separator: ",")
        guard parts.count == 3 || parts.count == 4,
              let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]),
              [r, g, b].allSatisfy({ (0...255).contains($0) })
        else { return nil }
        let a = parts.count == 4 ? (Double(parts[3]) ?? 1) : 1
        return NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: CGFloat(a))
    }

    static func hexString(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X",
            Int(round(c.redComponent * 255)),
            Int(round(c.greenComponent * 255)),
            Int(round(c.blueComponent * 255))
        )
    }

    static func rgbString(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return "rgb(\(Int(round(c.redComponent * 255))), \(Int(round(c.greenComponent * 255))), \(Int(round(c.blueComponent * 255))))"
    }

    // MARK: - JSON

    /// True if the text plausibly looks like JSON (starts with `{`/`[`), so we
    /// can offer JSON actions even when it turns out to be invalid.
    static func looksLikeJSON(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("{") || s.hasPrefix("[")
    }

    /// Returns the pretty-printed form if the text is valid JSON, else nil.
    static func prettyJSON(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeJSON(s),
              let data = s.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let string = String(data: pretty, encoding: .utf8)
        else { return nil }
        return string
    }

    // MARK: - QR

    /// Generates a QR code image for the text (skipping empty or very long text).
    static func qrImage(for text: String, scale: CGFloat = 10) -> NSImage? {
        guard !text.isEmpty, text.count <= 1200,
              let filter = CIFilter(name: "CIQRCodeGenerator")
        else { return nil }

        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
