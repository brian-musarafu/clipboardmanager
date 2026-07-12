import Carbon.HIToolbox
import SwiftData
import SwiftUI

/// The app's object graph: the SwiftData store, the view model, and the global
/// shortcut / quick-access wiring. Created once by `AppDelegate` and shared with
/// the SwiftUI scene so the menu-bar window and the ⌘⇧V panel stay in sync.
@MainActor
final class AppEnvironment {
    let container: ModelContainer
    let viewModel: ClipboardViewModel

    private let hotKeys = HotKeyManager()
    private lazy var quickAccessPanel = QuickAccessPanelController(
        rootView: AnyView(
            MainView()
                .environment(viewModel)
                .modelContainer(container)
        )
    )

    init() {
        do {
            container = try ModelContainer(for: ClipboardItem.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
        viewModel = ClipboardViewModel(modelContext: container.mainContext)
    }

    /// Registers global shortcuts. Call once, after the app finishes launching.
    func bootstrap() {
        // ⌘⇧V — summon / dismiss the quick-access panel.
        hotKeys.register(keyCode: kVK_ANSI_V, modifiers: HotKeyManager.command | HotKeyManager.shift) { [weak self] in
            self?.quickAccessPanel.toggle()
        }
        // ⌘⇧1 — paste the most recent pinned item into the frontmost app.
        hotKeys.register(keyCode: kVK_ANSI_1, modifiers: HotKeyManager.command | HotKeyManager.shift) { [weak self] in
            self?.viewModel.pasteMostRecentPinned()
        }

        if ProcessInfo.processInfo.environment["CLIP_SHOW_PANEL"] != nil {
            quickAccessPanel.show()
        }
    }
}
