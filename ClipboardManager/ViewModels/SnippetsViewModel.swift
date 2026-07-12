import Foundation
import SwiftData

/// Owns snippet CRUD and produces the expansion rules the `TextExpansionService`
/// runs. Notifies `onSnippetsChanged` after any edit so the active rules refresh.
@MainActor
@Observable
final class SnippetsViewModel {
    /// Called after any create/update/delete so the expander can reload rules.
    var onSnippetsChanged: (() -> Void)?

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func addSnippet() -> Snippet {
        let snippet = Snippet(title: "New Snippet", trigger: "", content: "")
        modelContext.insert(snippet)
        try? modelContext.save()
        onSnippetsChanged?()
        return snippet
    }

    /// Persists in-place edits made through `@Bindable` bindings.
    func save() {
        try? modelContext.save()
        onSnippetsChanged?()
    }

    func delete(_ snippet: Snippet) {
        modelContext.delete(snippet)
        try? modelContext.save()
        onSnippetsChanged?()
    }

    /// Current expansion rules for the keyboard tap.
    func currentRules() -> [TextExpansionService.Rule] {
        let snippets = (try? modelContext.fetch(FetchDescriptor<Snippet>())) ?? []
        return snippets.map { .init(trigger: $0.trigger, content: $0.content) }
    }

    /// Adds a starter `/sig` snippet the first time the app runs.
    func seedDefaultsIfEmpty() {
        let count = (try? modelContext.fetchCount(FetchDescriptor<Snippet>())) ?? 0
        guard count == 0 else { return }
        modelContext.insert(
            Snippet(
                title: "Signature",
                trigger: "/sig",
                content: "Kind Regards,\n\(NSFullUserName())"
            )
        )
        try? modelContext.save()
    }
}
