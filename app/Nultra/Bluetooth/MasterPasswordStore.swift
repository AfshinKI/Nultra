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
            throw StorageError.failed
        }
        return value
    }
    func save(_ value: String) throws {
        let data = try SwitchProtocol.eightASCII(value)
        let changes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StorageError.failed }
    }
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.failed }
    }
    enum StorageError: LocalizedError {
        case failed
        var errorDescription: String? { "Could not access the saved master password. Unlock your phone and save it again in Menu." }
    }
}
