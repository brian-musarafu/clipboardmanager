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

    /// Holds off App Nap so the clipboard-polling timer keeps firing while the app
    /// sits idle in the menu bar. Retained for the app's lifetime; released on quit.
    private var activityToken: NSObjectProtocol?

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
        container = Self.makeContainer()
        viewModel = ClipboardViewModel(modelContext: container.mainContext)
        snippetsViewModel = SnippetsViewModel(modelContext: container.mainContext)
    }

    /// Builds the SwiftData store — **explicitly local**.
    ///
    /// The models are already CloudKit-compatible (no unique constraints, every
    /// attribute defaulted). To turn on iCloud sync once the CloudKit capability
    /// is available, change `.none` to `.automatic` below and add the iCloud
    /// capability in Xcode.
    ///
    /// It is deliberately `.none` (not `.automatic`): with `.automatic` but no
    /// real iCloud account/entitlement, SwiftData still stands up CloudKit
    /// mirroring on the store, which destabilised the local history. Keep it
    /// local until sync is genuinely provisioned.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([ClipboardItem.self, Snippet.self])
        // Use a **dedicated, named** store — not SwiftData's default. The default
        // lands at the shared `~/Library/Application Support/default.store`, the
        // same path every other unsandboxed SwiftData app defaults to; another app
        // opening or resetting that file can silently wipe our history. A private
        // file at a deterministic path keeps the store ours alone.
        let configuration = ModelConfiguration(schema: schema, url: storeURL(), cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    /// `~/Library/Application Support/Clipio/Clipio.store`, creating the folder if
    /// needed. A fixed, app-specific location so history survives every relaunch.
    private static func storeURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Clipio", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Clipio.store")
    }

    /// Registers global shortcuts and starts text expansion. Call once, after the
    /// app finishes launching.
    func bootstrap() {
        // Keep the app out of App Nap so the pasteboard poll never gets throttled
        // to a stop. This allows normal system sleep but disables sudden/automatic
        // termination, so the SwiftData store also always closes cleanly.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Continuous clipboard monitoring"
        )

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
