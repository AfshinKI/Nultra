import Foundation
import Security

struct CredentialStore {
    private let service = "com.afshinki.nultra.ble"

    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    func read(_ id: UUID) throws -> Data? {
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError(status: status) }
        return result as? Data
    }

    func save(_ data: Data, for id: UUID) throws {
        let status = SecItemUpdate(query(id) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(id)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw StoreError(status: added) }
        } else if status != errSecSuccess {
            throw StoreError(status: status)
        }
    }

    func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError(status: status)
        }
    }

    struct StoreError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Could not access the saved switch password (Keychain \(status))." }
    }
}
