import Foundation
import CryptoKit

// iCloud Drive path — no entitlements needed, just a regular filesystem directory
// that macOS syncs automatically when iCloud Drive is enabled.
let kcDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/kc")

let saltFile: URL = kcDirectory.appendingPathComponent(".salt")

struct SecretEntry {
    let service: String
    let account: String
}

enum StorageError: Error {
    case notInitialised
    case notFound(String, String)
    case alreadyExists(String, String)
    case iCloudUnavailable

    var message: String {
        switch self {
        case .notInitialised:
            return "kc not initialised — run `kc init` first"
        case .notFound(let s, let a):
            return "not found: \(s)/\(a)"
        case .alreadyExists(let s, let a):
            return "\(s)/\(a) already exists — use `kc update \(s) \(a)` to overwrite"
        case .iCloudUnavailable:
            return "iCloud Drive directory not found — is iCloud Drive enabled?"
        }
    }
}

enum Storage {

    // MARK: - Init

    static func isInitialised() -> Bool {
        FileManager.default.fileExists(atPath: saltFile.path)
    }

    static func readSalt() throws -> Data {
        guard isInitialised() else { throw StorageError.notInitialised }
        return try Data(contentsOf: saltFile)
    }

    static func createVault(salt: Data) throws {
        let fm = FileManager.default
        // Verify iCloud Drive root exists (i.e. iCloud Drive is enabled)
        let iCloudRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard fm.fileExists(atPath: iCloudRoot.path) else {
            throw StorageError.iCloudUnavailable
        }
        try fm.createDirectory(at: kcDirectory, withIntermediateDirectories: true)
        try salt.write(to: saltFile, options: .atomic)
    }

    // MARK: - Write

    static func write(service: String, account: String, ciphertext: Data, overwrite: Bool = false) throws {
        let dir  = kcDirectory.appendingPathComponent(service)
        let file = dir.appendingPathComponent(account)
        if !overwrite && FileManager.default.fileExists(atPath: file.path) {
            throw StorageError.alreadyExists(service, account)
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try ciphertext.write(to: file, options: .atomic)
    }

    // MARK: - Read

    static func read(service: String, account: String) throws -> Data {
        let file = kcDirectory.appendingPathComponent(service).appendingPathComponent(account)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw StorageError.notFound(service, account)
        }
        return try Data(contentsOf: file)
    }

    // MARK: - Delete

    static func delete(service: String, account: String) throws {
        let file = kcDirectory.appendingPathComponent(service).appendingPathComponent(account)
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw StorageError.notFound(service, account)
        }
        try FileManager.default.removeItem(at: file)
        // Remove service dir if now empty
        let dir = kcDirectory.appendingPathComponent(service)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        if contents.isEmpty { try? FileManager.default.removeItem(at: dir) }
    }

    // MARK: - List

    static func list(service filterService: String? = nil) throws -> [SecretEntry] {
        guard isInitialised() else { throw StorageError.notInitialised }
        let fm = FileManager.default
        let services: [String]
        if let s = filterService {
            services = [s]
        } else {
            services = (try fm.contentsOfDirectory(atPath: kcDirectory.path))
                .filter { !$0.hasPrefix(".") }
                .sorted()
        }
        var entries: [SecretEntry] = []
        for service in services {
            let dir = kcDirectory.appendingPathComponent(service)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let accounts = (try? fm.contentsOfDirectory(atPath: dir.path))?.sorted() ?? []
            for account in accounts {
                entries.append(SecretEntry(service: service, account: account))
            }
        }
        return entries
    }
}
