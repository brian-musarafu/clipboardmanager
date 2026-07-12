import LocalAuthentication

/// Thin wrapper around Local Authentication for gating access to sensitive
/// items behind Touch ID (with password fallback).
enum AuthService {
    /// Whether the Mac can authenticate the owner at all (biometrics or password).
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Prompts for Touch ID / password. Returns true if the user authenticated.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            // No auth configured — fail open only in the sense that there's nothing
            // to check against; callers decide what that means for them.
            return true
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
