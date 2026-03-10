import Foundation
import Security
import CryptoKit

// LocalKeychain stores kc-internal metadata in the LOCAL login keychain.
// Never sets kSecAttrSynchronizable — intentionally stays on this machine.
// Two items: the master passphrase (for seamless re-derivation) and nothing else.
// The passphrase is the one secret that must be present per machine; everything
// else lives encrypted on iCloud Drive.

private let kcService        = "kc"
private let passphraseAccount = "passphrase"

enum LocalKeychainError: Error {
    case notFound
    case unexpectedStatus(OSStatus)

    var message: String {
        switch self {
        case .notFound: return "not initialised — run `kc init` first"
        case .unexpectedStatus(let s):
            return "Keychain error \(s): \(SecCopyErrorMessageString(s, nil) ?? "unknown" as CFString)"
        }
    }
}

enum LocalKeychain {

    // Upsert — always replaces existing entry
    static func savePassphrase(_ passphrase: String) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String:    kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: passphraseAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard let data = passphrase.data(using: .utf8) else { return }
        let addQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: passphraseAccount,
            kSecValueData as String:   data
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess { throw LocalKeychainError.unexpectedStatus(status) }
    }

    static func loadPassphrase() throws -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: kcService,
            kSecAttrAccount as String: passphraseAccount,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw LocalKeychainError.unexpectedStatus(-1)
            }
            return value
        case errSecItemNotFound: throw LocalKeychainError.notFound
        default:                 throw LocalKeychainError.unexpectedStatus(status)
        }
    }
}
