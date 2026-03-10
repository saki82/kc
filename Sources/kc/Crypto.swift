import Foundation
import CryptoKit
import CommonCrypto

enum CryptoError: Error {
    case keyDerivationFailed
    case encryptionFailed
    case decryptionFailed(String)

    var message: String {
        switch self {
        case .keyDerivationFailed:   return "key derivation failed"
        case .encryptionFailed:      return "encryption failed"
        case .decryptionFailed(let r): return "decryption failed: \(r) — wrong passphrase?"
        }
    }
}

enum Crypto {

    // MARK: - Salt

    static func generateSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return Data(bytes)
    }

    // MARK: - Key derivation (PBKDF2-SHA256, 200k iterations)

    static func deriveKey(passphrase: String, salt: Data) throws -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let saltBytes = Array(salt)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passphrase,
            passphrase.utf8.count,
            saltBytes,
            saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            200_000,
            &derived,
            32
        )
        guard status == kCCSuccess else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: Data(derived))
    }

    // MARK: - AES-256-GCM  (output: nonce || ciphertext || tag)

    static func encrypt(_ plaintext: String, key: SymmetricKey) throws -> Data {
        guard let data = plaintext.data(using: .utf8) else { throw CryptoError.encryptionFailed }
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw CryptoError.encryptionFailed }
        return combined
    }

    static func decrypt(_ ciphertext: Data, key: SymmetricKey) throws -> String {
        do {
            let box  = try AES.GCM.SealedBox(combined: ciphertext)
            let data = try AES.GCM.open(box, using: key)
            guard let string = String(data: data, encoding: .utf8) else {
                throw CryptoError.decryptionFailed("invalid UTF-8")
            }
            return string
        } catch let e as CryptoError {
            throw e
        } catch {
            throw CryptoError.decryptionFailed(error.localizedDescription)
        }
    }
}
