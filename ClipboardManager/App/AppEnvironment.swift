import Carbon.HIToolbox
import SwiftData
import SwiftUI

/// The app's object graph: the SwiftData store, view models, global shortcuts,
/// quick-access panel, snippet library, and text-expansion engine. Created once
/// by `AppDelegate` and shared with the SwiftUI scene so every surface stays in
/// sync.
@MainActor
final class AppEnvironment {
    let container: ModelContainer
    let viewModel: ClipboardViewModel
    let snippetsViewModel: SnippetsViewModel

    private let hotKeys = HotKeyManager()
    private let expander = TextExpansionService()

    private lazy var quickAccessPanel = QuickAccessPanelController(
        rootView: AnyView(
            MainView()
                .environment(viewModel)
                .modelContainer(container)
        )
    )

    private lazy var snippetsWindow = SnippetsWindowController(
        rootView: AnyView(
            SnippetsView()
                .environment(snippetsViewModel)
                .modelContainer(container)
        )
    )

    init() {
        do {
            container = try ModelContainer(for: ClipboardItem.self, Snippet.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        viewModel = ClipboardViewModel(modelContext: container.mainContext)
        snippetsViewModel = SnippetsViewModel(modelContext: container.mainContext)
    }

    /// Registers global shortcuts and starts text expansion. Call once, after the
    /// app finishes launching.
    func bootstrap() {
        // ⌘⇧V — summon / dismiss the quick-access panel.
        hotKeys.register(keyCode: kVK_ANSI_V, modifiers: HotKeyManager.command | HotKeyManager.shift) { [weak self] in
            self?.quickAccessPanel.toggle()
        }
        // ⌘⇧1 — paste the most recent pinned item into the frontmost app.
        hotKeys.register(keyCode: kVK_ANSI_1, modifiers: HotKeyManager.command | HotKeyManager.shift) { [weak self] in
            self?.viewModel.pasteMostRecentPinned()
        }

        // Let the menu-bar UI open the snippet library.
        viewModel.openSnippets = { [weak self] in
            self?.snippetsWindow.show()
        }

        // Snippets & text expansion.
        snippetsViewModel.seedDefaultsIfEmpty()
        snippetsViewModel.onSnippetsChanged = { [weak self] in
            guard let self else { return }
            self.expander.setRules(self.snippetsViewModel.currentRules())
        }
        expander.setRules(snippetsViewModel.currentRules())
        expander.start()
    }
}
