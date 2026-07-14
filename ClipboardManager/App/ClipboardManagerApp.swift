import SwiftData
import SwiftUI

@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Clipio", systemImage: "doc.on.clipboard") {
            MainView()
                .environment(appDelegate.environment.viewModel)
                .modelContainer(appDelegate.environment.container)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the shared object graph and registers global shortcuts once the app has
/// launched (the point at which Carbon's application event target is ready).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment.bootstrap()
    }

    /// Final flush on quit. Sudden termination is disabled (see `bootstrap`), so
    /// this is guaranteed to run and checkpoint any pending writes to the store.
    func applicationWillTerminate(_ notification: Notification) {
        try? environment.container.mainContext.save()
    }
}
