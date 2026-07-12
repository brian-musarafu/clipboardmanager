import AppKit
import Foundation
import SwiftData

/// A single entry in the clipboard history.
///
/// `type` is kept as a `String` (rather than the enum directly) so the persisted
/// schema stays stable as new content kinds are added — see `ItemType`.
///
/// Content is stored per kind:
/// - text/code/url/note → `content` holds the string.
/// - file → `content` holds the file's absolute path.
/// - image → `imageData` holds PNG bytes and `content` holds a short caption.
@Model
final class ClipboardItem {
    /// Stable identity. Not marked `.unique` because CloudKit sync (Phase 7)
    /// disallows uniqueness constraints; de-duplication is handled in the view
    /// model by content instead.
    var id: UUID = UUID()

    /// Text content, a file path (for `.file`), or a caption (for `.image`).
    var content: String = ""

    /// Raw value of an `ItemType`.
    var type: String = ItemType.text.rawValue

    /// When the content was captured.
    var createdAt: Date = Date.now

    /// Pinned items are surfaced above the recent list and never auto-trimmed.
    var isPinned: Bool = false

    /// Marked as a favorite by the user.
    var isFavorite: Bool = false

    /// PNG bytes for `.image` entries. Stored outside the database file so large
    /// screenshots don't bloat the store. Optional — this is a lightweight,
    /// migration-safe addition to the Phase 1–2 schema.
    @Attribute(.externalStorage) var imageData: Data?

    /// Heuristically detected secret (e.g. a card number). Redacted in the UI and
    /// revealed only after authentication.
    var isSensitive: Bool = false

    /// Whether `content` holds ciphertext (see `CryptoService`). Sensitive items
    /// are encrypted at rest so the raw store never exposes the secret.
    var isEncrypted: Bool = false

    init(
        content: String,
        type: ItemType = .text,
        createdAt: Date = .now,
        isPinned: Bool = false,
        isFavorite: Bool = false,
        imageData: Data? = nil,
        isSensitive: Bool = false,
        isEncrypted: Bool = false
    ) {
        self.id = UUID()
        self.content = content
        self.type = type.rawValue
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.imageData = imageData
        self.isSensitive = isSensitive
        self.isEncrypted = isEncrypted
    }

    /// Typed accessor for `type`, falling back to `.text` for unknown values.
    var kind: ItemType {
        ItemType(rawValue: type) ?? .text
    }

    // MARK: - Rich-content helpers

    /// The file URL for `.file` entries.
    var fileURL: URL? {
        kind == .file ? URL(fileURLWithPath: content) : nil
    }

    /// The decoded image for `.image` entries.
    var image: NSImage? {
        guard kind == .image, let imageData else { return nil }
        return NSImage(data: imageData)
    }

    /// What to show as the row's primary label.
    var displayText: String {
        switch kind {
        case .file: (content as NSString).lastPathComponent
        default: content
        }
    }
}

/// The kind of a clipboard entry. Text kinds are classified heuristically on
/// capture (Phase 4 upgrades this); image/file are detected from the pasteboard.
enum ItemType: String, CaseIterable {
    case text
    case code
    case url
    case note
    case image
    case file

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .url: "link"
        case .note: "note.text"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var label: String {
        switch self {
        case .text: "Text"
        case .code: "Code"
        case .url: "URL"
        case .note: "Note"
        case .image: "Image"
        case .file: "File"
        }
    }
}
