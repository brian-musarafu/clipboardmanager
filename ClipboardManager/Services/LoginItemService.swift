import ServiceManagement

/// Registers the app to launch automatically at login, using the modern
/// `SMAppService` API (macOS 13+). No helper bundle or entitlement required —
/// the app registers itself.
enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItemService: failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }
}
