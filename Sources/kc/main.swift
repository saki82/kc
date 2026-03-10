import Foundation
import CryptoKit

// ---------------------------------------------------------------------------
// kc — encrypted secret store synced via iCloud Drive
//
// Secrets are AES-256-GCM encrypted JSON, stored as files under:
//   ~/Library/Mobile Documents/com~apple~CloudDocs/kc/<service>/<account>
//
// Each secret is a named bag of fields:
//   kc set homelab shopify        → interactive: api-key, api-secret, endpoint...
//   kc get homelab shopify        → shows all fields
//   kc get homelab shopify api-key → raw value of that field (pipeable)
//
// Single-value secrets use the reserved field name "value":
//   kc set homelab cloudflare-token  → press Enter at field prompt → just a value
//   kc get homelab cloudflare-token  → prints the raw value directly
//
// Commands:
//   kc init                                    First-time setup or restore
//   kc set    <service> <account>              Store a secret (interactive field loop)
//   kc get    <service> <account> [field]      All fields or specific field (raw)
//   kc update <service> <account> [field]      Update one field (or single value)
//   kc delete <service> <account> [field]      Delete field or entire secret
//   kc list   [<service>]         [--json]     List secrets — never shows values
// ---------------------------------------------------------------------------

let argv = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    kc — encrypted secret store synced via iCloud Drive

    Usage:
      kc init                                  First-time setup or restore on new machine
      kc set    <service> <account>            Store a secret (interactive field loop)
      kc get    <service> <account> [field]    Show all fields or retrieve one (raw, pipeable)
      kc update <service> <account> [field]    Update a field (or the single value)
      kc delete <service> <account> [field]    Delete a field or the entire secret
      kc list   [<service>]        [--json]    List stored secrets — never shows values

    Single-value example:
      kc set    homelab cloudflare-token       # press Enter at field prompt
      kc get    homelab cloudflare-token       # prints raw value

    Multi-field example:
      kc set    homelab shopify                # enter api-key, api-secret, endpoint...
      kc get    homelab shopify                # shows field table
      kc get    homelab shopify api-key        # prints raw value of that field
      kc update homelab shopify api-secret     # replaces just that field
      kc delete homelab shopify endpoint       # removes just that field

    Scripting:
      Set KC_PASSPHRASE in the environment to bypass all prompts and Keychain access.
      export TOKEN=$(kc get homelab cloudflare-token)
    """)
    exit(0)
}

guard let command = argv.first else { usage() }
if command == "-h" || command == "--help" { usage() }

let flags      = Set(argv.dropFirst().filter { $0.hasPrefix("--") })
let positional = argv.dropFirst().filter { !$0.hasPrefix("--") }
let wantsJSON  = flags.contains("--json")

// MARK: - Key resolution
// Priority: KC_PASSPHRASE env var → local Keychain → interactive prompt

func resolveKey() -> SymmetricKey {
    guard Storage.isInitialised() else {
        fail("kc not initialised — run `kc init` first")
    }
    let salt: Data
    do { salt = try Storage.readSalt() }
    catch { fail("could not read salt: \(error)") }

    if let envPassphrase = ProcessInfo.processInfo.environment["KC_PASSPHRASE"],
       !envPassphrase.isEmpty {
        do { return try Crypto.deriveKey(passphrase: envPassphrase, salt: salt) }
        catch { fail("key derivation failed with KC_PASSPHRASE") }
    }
    if let stored = try? LocalKeychain.loadPassphrase() {
        do { return try Crypto.deriveKey(passphrase: stored, salt: salt) }
        catch { fail("key derivation failed: \(error)") }
    }
    guard let passphrase = readSecret(prompt: "Master passphrase: "),
          !passphrase.isEmpty else { fail("passphrase cannot be empty") }
    do { return try Crypto.deriveKey(passphrase: passphrase, salt: salt) }
    catch { fail("key derivation failed: \(error)") }
}

// MARK: - Payload helpers

func loadPayload(service: String, account: String, key: SymmetricKey) -> SecretPayload {
    do {
        let ciphertext = try Storage.read(service: service, account: account)
        let plaintext  = try Crypto.decrypt(ciphertext, key: key)
        return SecretPayload(from: plaintext)
    } catch let e as StorageError { fail(e.message) }
    catch let e as CryptoError   { fail(e.message) }
    catch                         { fail("\(error)") }
}

func savePayload(_ payload: SecretPayload, service: String, account: String,
                 key: SymmetricKey, overwrite: Bool) {
    do {
        let plaintext  = try payload.serialised()
        let ciphertext = try Crypto.encrypt(plaintext, key: key)
        try Storage.write(service: service, account: account,
                          ciphertext: ciphertext, overwrite: overwrite)
    } catch let e as StorageError { fail(e.message) }
    catch let e as CryptoError   { fail(e.message) }
    catch let e as PayloadError  { fail(e.message) }
    catch                         { fail("\(error)") }
}

// MARK: - Commands

switch command {

// MARK: init
case "init":
    if Storage.isInitialised() {
        print("Restoring kc on this machine (vault found in iCloud Drive).")
        guard let passphrase = readSecret(prompt: "Master passphrase: "),
              !passphrase.isEmpty else { fail("passphrase cannot be empty") }
        let salt = (try? Storage.readSalt()) ?? Data()
        guard (try? Crypto.deriveKey(passphrase: passphrase, salt: salt)) != nil else {
            fail("key derivation failed")
        }
        do {
            try LocalKeychain.savePassphrase(passphrase)
            print("✓ Passphrase stored locally. All existing secrets are now accessible.")
        } catch { fail("could not save passphrase to local Keychain: \(error)") }
    } else {
        guard let passphrase = readSecret(prompt: "Master passphrase: "),
              !passphrase.isEmpty else { fail("passphrase cannot be empty") }
        guard let confirm = readSecret(prompt: "Confirm passphrase: "),
              confirm == passphrase else { fail("passphrases do not match") }
        let salt = Crypto.generateSalt()
        do {
            try Storage.createVault(salt: salt)
            try LocalKeychain.savePassphrase(passphrase)
            print("✓ Vault created in iCloud Drive. Passphrase stored locally.")
            print("  Syncing will begin automatically.")
        } catch let e as StorageError { fail(e.message) }
        catch { fail("init failed: \(error)") }
    }

// MARK: set
case "set":
    guard positional.count >= 2 else { fail("usage: kc set <service> <account>") }
    let service = positional[0], account = positional[1]
    let key = resolveKey()

    // Interactive field loop
    // Pressing Enter on the first field name → single-value mode (field = "value")
    var fields: [String: String] = [:]
    print("Enter fields for \(service)/\(account).")
    print("Press Enter with no field name for a single-value secret, or to finish.")
    while true {
        let isFirst = fields.isEmpty
        let prompt  = isFirst ? "Field name (Enter = single value): "
                               : "Field name (Enter to finish):      "
        print(prompt, terminator: "")
        fflush(stdout)
        let fieldName = readLine(strippingNewline: true) ?? ""
        if fieldName.isEmpty {
            if isFirst {
                // Single-value mode
                guard let val = readSecret(prompt: "Secret: "),
                      !val.isEmpty else { fail("secret cannot be empty") }
                fields["value"] = val
            }
            break
        }
        guard let val = readSecret(prompt: "Value for '\(fieldName)': "),
              !val.isEmpty else { fail("value cannot be empty") }
        fields[fieldName] = val
    }

    let payload = SecretPayload(fields: fields)
    savePayload(payload, service: service, account: account, key: key, overwrite: false)
    if payload.isSingleValue {
        print("✓ Stored \(service)/\(account)")
    } else {
        print("✓ Stored \(service)/\(account) (\(fields.count) fields: \(payload.sortedKeys.joined(separator: ", ")))")
    }

// MARK: get
case "get":
    guard positional.count >= 2 else { fail("usage: kc get <service> <account> [field]") }
    let service = positional[0], account = positional[1]
    let field   = positional.count >= 3 ? positional[2] : nil
    let key     = resolveKey()
    let payload = loadPayload(service: service, account: account, key: key)

    if let field {
        // Specific field → raw output (pipeable)
        guard let value = payload.fields[field] else {
            fail("field '\(field)' not found in \(service)/\(account). " +
                 "Available: \(payload.sortedKeys.joined(separator: ", "))")
        }
        print(value)
    } else if payload.isSingleValue {
        // Single-value secret → raw output for backwards compat
        print(payload.fields["value"]!)
    } else {
        // Multi-field → table or JSON
        if wantsJSON { printFieldJSON(service: service, account: account, payload: payload) }
        else          { printFieldTable(service: service, account: account, payload: payload) }
    }

// MARK: update
case "update":
    guard positional.count >= 2 else { fail("usage: kc update <service> <account> [field]") }
    let service = positional[0], account = positional[1]
    let field   = positional.count >= 3 ? positional[2] : nil
    let key     = resolveKey()
    var payload = loadPayload(service: service, account: account, key: key)

    let targetField: String
    if let field {
        guard payload.fields[field] != nil else {
            fail("field '\(field)' not found in \(service)/\(account). " +
                 "Available: \(payload.sortedKeys.joined(separator: ", "))")
        }
        targetField = field
    } else if payload.isSingleValue {
        targetField = "value"
    } else {
        fail("'\(service)/\(account)' has multiple fields — specify one: \(payload.sortedKeys.joined(separator: ", "))")
    }

    guard let newValue = readSecret(prompt: "New value for '\(targetField)': "),
          !newValue.isEmpty else { fail("value cannot be empty") }
    payload.fields[targetField] = newValue
    savePayload(payload, service: service, account: account, key: key, overwrite: true)
    print("✓ Updated \(service)/\(account)/\(targetField)")

// MARK: delete
case "delete":
    guard positional.count >= 2 else { fail("usage: kc delete <service> <account> [field]") }
    let service = positional[0], account = positional[1]
    let field   = positional.count >= 3 ? positional[2] : nil
    let key     = resolveKey()

    if let field {
        // Delete a single field from the payload
        var payload = loadPayload(service: service, account: account, key: key)
        guard payload.fields[field] != nil else {
            fail("field '\(field)' not found in \(service)/\(account). " +
                 "Available: \(payload.sortedKeys.joined(separator: ", "))")
        }
        guard confirm("Remove field '\(field)' from \(service)/\(account)? [y/N] ") else {
            print("Cancelled."); exit(0)
        }
        payload.fields.removeValue(forKey: field)
        if payload.fields.isEmpty {
            // Last field removed → delete the file entirely
            do { try Storage.delete(service: service, account: account) }
            catch let e as StorageError { fail(e.message) }
            print("✓ Deleted \(service)/\(account) (no fields remaining)")
        } else {
            savePayload(payload, service: service, account: account, key: key, overwrite: true)
            print("✓ Removed field '\(field)' from \(service)/\(account)")
        }
    } else {
        // Delete the entire secret
        guard confirm("Delete \(service)/\(account)? [y/N] ") else { print("Cancelled."); exit(0) }
        do { try Storage.delete(service: service, account: account) }
        catch let e as StorageError { fail(e.message) }
        print("✓ Deleted \(service)/\(account)")
    }

// MARK: list
case "list":
    let service: String? = positional.first
    do {
        let items = try Storage.list(service: service)
        if items.isEmpty {
            let scope = service.map { " for '\($0)'" } ?? ""
            print("No secrets stored\(scope).")
        } else if wantsJSON { printJSON(items) }
        else                 { printTable(items) }
    } catch let e as StorageError { fail(e.message) }
    catch                         { fail("\(error)") }

default:
    fputs("error: unknown command '\(command)'\n\n", stderr)
    usage()
}
