import Foundation

/// The category tabs shown in the history filter bar. Maps the stored
/// `ItemType` of each entry onto a small, user-facing set of buckets.
enum CategoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case code
    case url
    case image
    case file

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .code: "Code"
        case .url: "Links"
        case .image: "Images"
        case .file: "Files"
        }
    }

    /// Whether an item belongs in this category.
    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: true
        case .text: item.kind == .text || item.kind == .note
        case .code: item.kind == .code
        case .url: item.kind == .url
        case .image: item.kind == .image
        case .file: item.kind == .file
        }
    }
}
