import Foundation
import SwiftData

/// A reusable text template. Typing its `trigger` (e.g. `/sig`) anywhere expands
/// it into `content`, with `{{variables}}` resolved at expansion time.
@Model
final class Snippet {
    @Attribute(.unique) var id: UUID
    var title: String
    var trigger: String
    var content: String
    var createdAt: Date

    init(title: String = "New Snippet", trigger: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.trigger = trigger
        self.content = content
        self.createdAt = .now
    }
}
