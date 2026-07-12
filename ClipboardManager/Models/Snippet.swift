import Foundation
import SwiftData

/// A reusable text template. Typing its `trigger` (e.g. `/sig`) anywhere expands
/// it into `content`, with `{{variables}}` resolved at expansion time.
@Model
final class Snippet {
    // Defaults on every attribute (and no `.unique`) so the model is compatible
    // with CloudKit sync.
    var id: UUID = UUID()
    var title: String = ""
    var trigger: String = ""
    var content: String = ""
    var createdAt: Date = Date.now

    init(title: String = "New Snippet", trigger: String = "", content: String = "") {
        self.id = UUID()
        self.title = title
        self.trigger = trigger
        self.content = content
        self.createdAt = .now
    }
}
