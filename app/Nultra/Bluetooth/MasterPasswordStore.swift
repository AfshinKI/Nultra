import Foundation
import Security

struct MasterPasswordStore {
    let account: String
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.afshinki.nultra.master-password",
         kSecAttrAccount as String: account]
    }
    func load() throws -> String {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .ascii), (try? SwitchProtocol.eightASCII(value)) != nil else {
            throw StorageError.failed(status: status)
        }
        // Upgrade existing entries while unlocked; later background shortcuts can read them
        // after the first device unlock following a restart, without cloud/device migration.
        SecItemUpdate(query as CFDictionary, [kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary)
        return value
    }
    func save(_ value: String) throws {
        let data = try SwitchProtocol.eightASCII(value)
        let changes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageError.failed(status: status) }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.failed(status: status) }
    }
    enum StorageError: LocalizedError {
        case failed(status: OSStatus)
        var errorDescription: String? {
            switch self {
            case .failed(let status):
                return "Could not access the saved master password (Keychain \(status)). Unlock your phone and save it again in Menu."
            }
        }
    }
}
