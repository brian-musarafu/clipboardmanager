import CryptoKit
import Foundation
import Security

/// AES-256-GCM encryption for sensitive clipboard content, keyed by a 256-bit
/// symmetric key stored in the login Keychain. Encrypting at rest means the raw
/// SwiftData store never contains the plaintext secret.
enum CryptoService {
    private static let keychainService = "com.brianmusarafu.ClipboardManager.encryptionKey"
    private static let keychainAccount = "primary"

    /// The symmetric key, loaded from the Keychain (created on first use).
    private static let key: SymmetricKey = loadOrCreateKey()

    /// Encrypts `plaintext`, returning a base64 string, or nil on failure.
    static func encryptToString(_ plaintext: String) -> String? {
        guard let data = plaintext.data(using: .utf8),
              let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined
        else { return nil }
        return combined.base64EncodedString()
    }

    /// Decrypts a base64 string produced by `encryptToString`, or nil on failure.
    static func decryptFromString(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: key)
        else { return nil }
        return String(data: opened, encoding: .utf8)
    }

    // MARK: - Keychain-backed key

    private static func loadOrCreateKey() -> SymmetricKey {
        if let data = readKey() {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        key.withUnsafeBytes { storeKey(Data($0)) }
        return key
    }

    private static func readKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func storeKey(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
