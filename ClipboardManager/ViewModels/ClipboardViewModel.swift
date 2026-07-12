import AppKit
import Foundation
import SwiftData

/// Coordinates clipboard capture and the actions the UI performs on history
/// items. Views read the history through `@Query`, so this view model owns the
/// *write* side: it starts the monitor, inserts captured text, and mutates
/// items (copy back, pin, delete).
@MainActor
@Observable
final class ClipboardViewModel {
    /// Live search text bound to the search field.
    var searchText: String = ""

    /// Most recent history is trimmed to this many *unpinned* items so the store
    /// doesn't grow without bound. Pinned items are always kept.
    let historyLimit = 100

    /// The container's main context. This is the same context `@Query` reads
    /// from (via `.modelContainer`), so captures appear in the UI immediately.
    private let modelContext: ModelContext
    private let monitor = ClipboardMonitor()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        monitor.onNewContent = { [weak self] payload in
            self?.capture(payload)
        }
        monitor.start()
    }

    // MARK: - Capture

    private func capture(_ payload: ClipboardPayload) {
        switch payload {
        case .text(let text):
            captureText(text)
        case .image(let data):
            captureImage(data)
        case .files(let urls):
            captureFiles(urls)
        }
    }

    private func captureText(_ text: String) {
        // Skip if identical to the newest stored item (e.g. rapid re-copies, or
        // our own write-back that slipped past `suppress`).
        if let newest = fetchNewest(), newest.kind != .image, newest.content == text {
            newest.createdAt = .now
            try? modelContext.save()
            return
        }
        insert(ClipboardItem(content: text, type: detectType(text)))
    }

    private func captureImage(_ data: Data) {
        // De-dupe against an immediately repeated image.
        if let newest = fetchNewest(), newest.kind == .image, newest.imageData == data {
            newest.createdAt = .now
            try? modelContext.save()
            return
        }
        let caption: String
        if let image = NSImage(data: data) {
            caption = "Image \(Int(image.size.width))×\(Int(image.size.height))"
        } else {
            caption = "Image"
        }
        insert(ClipboardItem(content: caption, type: .image, imageData: data))
    }

    private func captureFiles(_ urls: [URL]) {
        // One entry per file so previews and drag-and-drop stay per-item. Skip a
        // file that's already the newest entry.
        for url in urls {
            let path = url.path
            if let newest = fetchNewest(), newest.kind == .file, newest.content == path {
                newest.createdAt = .now
                try? modelContext.save()
                continue
            }
            insert(ClipboardItem(content: path, type: .file))
        }
    }

    /// Inserts and persists a new item, then trims old history.
    ///
    /// IMPORTANT: save the insert on its own before doing any fetch. Running a
    /// fetch (as `trimHistory` does) while an insert is still pending leaves the
    /// context in a state where the subsequent `save()` silently commits nothing.
    /// Persisting first, then trimming, keeps every capture durable.
    private func insert(_ item: ClipboardItem) {
        modelContext.insert(item)
        try? modelContext.save()
        trimHistory()
    }

    /// Lightweight content classification used to tag captured items. Heuristic
    /// for now; Phase 4 replaces it with real data detection.
    private func detectType(_ text: String) -> ItemType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isWebLink(trimmed) { return .url }
        if looksLikeCode(trimmed) { return .code }
        return .text
    }

    private func isWebLink(_ trimmed: String) -> Bool {
        guard !trimmed.contains(" "),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return false }
        return true
    }

    private func looksLikeCode(_ trimmed: String) -> Bool {
        // JSON / array literals.
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
           (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return true
        }
        // Common language keywords / markers.
        let markers = ["func ", "class ", "struct ", "import ", "def ", "const ",
                       "function ", "public ", "private ", "#include", "<html",
                       "</", "SELECT ", "=> ", "println", "console.log"]
        if markers.contains(where: { trimmed.contains($0) }) { return true }
        // Several lines that look statement-like (braces or semicolons).
        let codeyLines = trimmed.split(separator: "\n").filter {
            $0.contains(";") || $0.contains("{") || $0.contains("}")
        }
        return codeyLines.count >= 2
    }

    // MARK: - Item actions

    /// Primary action when a history row is clicked:
    /// - a link is opened in the default browser (a new tab), and
    /// - anything else is pasted into whatever field was focused before the
    ///   menu-bar window opened.
    func activate(_ item: ClipboardItem) {
        // Bump recency first (plain mutation — safe to save).
        item.createdAt = .now
        try? modelContext.save()

        if let url = linkURL(for: item) {
            NSApp.hide(nil) // return focus to the previous app / browser
            NSWorkspace.shared.open(url)
        } else {
            paste(item)
        }
    }

    /// Copies the item without pasting (used from the context menu).
    func copyToClipboard(_ item: ClipboardItem) {
        writeToPasteboard(item)
        item.createdAt = .now
        try? modelContext.save()
    }

    /// Opens a `.file` item in its default app, or reveals it in Finder.
    func openFile(_ item: ClipboardItem) {
        guard let url = item.fileURL else { return }
        NSApp.hide(nil)
        NSWorkspace.shared.open(url)
    }

    func revealInFinder(_ item: ClipboardItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Smart actions (Phase 4)

    /// Puts an arbitrary string on the pasteboard (e.g. a shortened URL, a
    /// pretty-printed JSON blob, or a color value) without pasting.
    func copyString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        monitor.suppress()
    }

    /// Opens a URL in the default browser.
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Opens a new mail compose window addressed to `address`.
    func composeEmail(to address: String) {
        guard let url = URL(string: "mailto:\(address)") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Shortens a URL via the free is.gd service. Returns the short URL, or nil
    /// on failure. This sends the URL to a third party, so it's only ever called
    /// from an explicit user action.
    func shortenURL(_ url: URL) async -> String? {
        var components = URLComponents(string: "https://is.gd/create.php")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "simple"),
            URLQueryItem(name: "url", value: url.absoluteString),
        ]
        guard let endpoint = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let short = String(data: data, encoding: .utf8)?
                      .trimmingCharacters(in: .whitespacesAndNewlines),
                  short.hasPrefix("http")
            else { return nil }
            return short
        } catch {
            return nil
        }
    }

    /// Global-shortcut action (⌘⇧1): paste the most recently used pinned item
    /// straight into the frontmost app. Our app isn't active here, so there's no
    /// window to dismiss — we set the pasteboard and send ⌘V directly.
    func pasteMostRecentPinned() {
        guard let item = mostRecentPinned() else {
            NSSound.beep()
            return
        }
        writeToPasteboard(item)
        item.createdAt = .now
        try? modelContext.save()
        PasteService.pasteToFrontmostApp()
    }

    /// Places the item on the pasteboard, dismisses our window so the previously
    /// active app regains focus, then sends ⌘V into it.
    private func paste(_ item: ClipboardItem) {
        writeToPasteboard(item)

        NSApp.hide(nil)
        // Give macOS a beat to reactivate the previous app before pasting.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            PasteService.pasteToFrontmostApp()
        }
    }

    /// Writes the item onto the system pasteboard using the representation that
    /// matches its kind, so it pastes correctly into other apps.
    private func writeToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .image:
            if let image = item.image {
                pasteboard.writeObjects([image])
            }
        case .file:
            if let url = item.fileURL {
                pasteboard.writeObjects([url as NSURL])
            }
        default:
            pasteboard.setString(item.content, forType: .string)
        }
        monitor.suppress() // don't re-capture our own write
    }

    /// Returns an http/https URL if the item's content is a web link, else nil.
    func linkURL(for item: ClipboardItem) -> URL? {
        let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(" "),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }

    func togglePin(_ item: ClipboardItem) {
        item.isPinned.toggle()
        try? modelContext.save()
    }

    func toggleFavorite(_ item: ClipboardItem) {
        item.isFavorite.toggle()
        try? modelContext.save()
    }

    func delete(_ item: ClipboardItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    /// Removes every non-pinned item.
    func clearHistory() {
        let pinned = FetchDescriptor<ClipboardItem>(predicate: #Predicate { !$0.isPinned })
        if let items = try? modelContext.fetch(pinned) {
            for item in items { modelContext.delete(item) }
            try? modelContext.save()
        }
    }

    // MARK: - Helpers

    private func fetchNewest() -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func mostRecentPinned() -> ClipboardItem? {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.isPinned },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Deletes unpinned items beyond `historyLimit`. Call this only when there
    /// are no pending unsaved changes on the context (see the note in
    /// `capture`); it fetches, deletes, and saves as its own unit of work.
    private func trimHistory() {
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchOffset = historyLimit
        guard let stale = try? modelContext.fetch(descriptor), !stale.isEmpty else { return }
        for item in stale { modelContext.delete(item) }
        try? modelContext.save()
    }
}
