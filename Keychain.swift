import Foundation
import Security

// kc tags every item it writes so list/delete only operate on its own items.
// This prevents accidentally polluting or listing unrelated keychain entries.
private let kcLabel = "kc"

enum KeychainError: Error {
    case notFound
    case duplicateItem
    case unexpectedStatus(OSStatus)

    var message: String {
        switch self {
        case .notFound:
            return "item not found"
        case .duplicateItem:
            return "item already exists — use `kc update` to overwrite"
        case .unexpectedStatus(let s):
            return "Security framework error \(s): \(SecCopyErrorMessageString(s, nil) ?? "unknown" as CFString)"
        }
    }
}

struct KeychainEntry {
    let service: String
    let account: String
}

enum Keychain {

    // MARK: - Write

    static func set(service: String, account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedStatus(-1)
        }
        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrService as String:         service,
            kSecAttrAccount as String:         account,
            kSecAttrLabel as String:           kcLabel,
            kSecValueData as String:           data,
            kSecAttrSynchronizable as String:  true   // ← iCloud sync
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:     return
        case errSecDuplicateItem: throw KeychainError.duplicateItem
        default:                throw KeychainError.unexpectedStatus(status)
        }
    }

    static func update(service: String, account: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedStatus(-1)
        }
        // Match on both sync and non-sync so a previously local item can be
        // promoted to synced on first update.
        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrService as String:         service,
            kSecAttrAccount as String:         account,
            kSecAttrSynchronizable as String:  kSecAttrSynchronizableAny
        ]
        let attributes: [String: Any] = [
            kSecValueData as String:           data,
            kSecAttrSynchronizable as String:  true,
            kSecAttrLabel as String:           kcLabel
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:      return
        case errSecItemNotFound: throw KeychainError.notFound
        default:                 throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Read

    static func get(service: String, account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrService as String:         service,
            kSecAttrAccount as String:         account,
            kSecAttrSynchronizable as String:  kSecAttrSynchronizableAny,
            kSecReturnData as String:          true,
            kSecMatchLimit as String:          kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedStatus(-1)
            }
            return value
        case errSecItemNotFound: throw KeychainError.notFound
        default:                 throw KeychainError.unexpectedStatus(status)
        }
    }

    static func list(service: String? = nil) throws -> [KeychainEntry] {
        var query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrLabel as String:           kcLabel,       // only kc-managed items
            kSecAttrSynchronizable as String:  kSecAttrSynchronizableAny,
            kSecReturnAttributes as String:    true,
            kSecMatchLimit as String:          kSecMatchLimitAll
        ]
        if let service {
            query[kSecAttrService as String] = service
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let items = result as? [[String: Any]] else { return [] }
            return items.compactMap { item -> KeychainEntry? in
                guard let svc = item[kSecAttrService as String] as? String,
                      let acc = item[kSecAttrAccount as String] as? String
                else { return nil }
                return KeychainEntry(service: svc, account: acc)
            }
            .sorted {
                $0.service == $1.service
                    ? $0.account < $1.account
                    : $0.service < $1.service
            }
        case errSecItemNotFound: return []
        default:                 throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Delete

    static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrService as String:         service,
            kSecAttrAccount as String:         account,
            kSecAttrSynchronizable as String:  kSecAttrSynchronizableAny
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess:      return
        case errSecItemNotFound: throw KeychainError.notFound
        default:                 throw KeychainError.unexpectedStatus(status)
        }
    }
}
