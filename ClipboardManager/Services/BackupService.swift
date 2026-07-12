import Foundation

/// Serialises history and snippets to a portable backup file, and reads them
/// back. Sensitive items are deliberately excluded — a backup is a plaintext
/// file, so secrets never leave the encrypted store.
enum BackupService {
    static let formatVersion = 1

    // MARK: - DTOs

    struct Payload: Codable {
        var version: Int
        var exportedAt: Date
        var items: [Item]
        var snippets: [SnippetDTO]
    }

    struct Item: Codable {
        var type: String
        var content: String
        var createdAt: Date
        var isPinned: Bool
        var isFavorite: Bool
        var imageBase64: String?
    }

    struct SnippetDTO: Codable {
        var title: String
        var trigger: String
        var content: String
    }

    // MARK: - Encoding

    static func encodeJSON(items: [ClipboardItem], snippets: [Snippet]) throws -> Data {
        let payload = Payload(
            version: formatVersion,
            exportedAt: .now,
            items: items.filter { !$0.isSensitive }.map(dto(for:)),
            snippets: snippets.map { SnippetDTO(title: $0.title, trigger: $0.trigger, content: $0.content) }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// History as CSV (images and sensitive items omitted). One row per item.
    static func encodeCSV(items: [ClipboardItem]) -> String {
        var lines = ["type,content,createdAt,isPinned,isFavorite"]
        let formatter = ISO8601DateFormatter()
        for item in items where !item.isSensitive && item.kind != .image {
            let fields = [
                item.type,
                item.content,
                formatter.string(from: item.createdAt),
                String(item.isPinned),
                String(item.isFavorite),
            ]
            lines.append(fields.map(csvEscaped).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Decoding

    static func decodeJSON(_ data: Data) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Payload.self, from: data)
    }

    // MARK: - Helpers

    private static func dto(for item: ClipboardItem) -> Item {
        Item(
            type: item.type,
            content: item.content,
            createdAt: item.createdAt,
            isPinned: item.isPinned,
            isFavorite: item.isFavorite,
            imageBase64: item.imageData?.base64EncodedString()
        )
    }

    private static func csvEscaped(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
