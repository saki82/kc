import Foundation

// ---------------------------------------------------------------------------
// kc — iCloud Keychain CLI
//
// Wraps the Security framework with kSecAttrSynchronizable:true so every
// secret syncs across your Apple devices via iCloud Keychain automatically.
//
// Usage:
//   kc set    <service> <account>           Store a secret (echo-free prompt)
//   kc get    <service> <account> [--json]  Print the secret value
//   kc update <service> <account>           Overwrite an existing secret
//   kc delete <service> <account>           Delete with confirmation
//   kc list   [<service>]        [--json]   List items — never shows values
//
// Naming convention: service = logical group (homelab, bizpulse)
//                    account = specific key  (cloudflare-token, stripe-key)
// ---------------------------------------------------------------------------

let argv = Array(CommandLine.arguments.dropFirst())

func usage() -> Never {
    print("""
    kc — iCloud Keychain CLI (syncs across all your Apple devices)

    Usage:
      kc set    <service> <account>           Store a secret
      kc get    <service> <account> [--json]  Retrieve a secret
      kc update <service> <account>           Overwrite an existing secret
      kc delete <service> <account>           Delete a secret
      kc list   [<service>]        [--json]   List stored items

    Examples:
      kc set homelab cloudflare-token
      kc set bizpulse stripe-secret-key
      kc get homelab cloudflare-token
      kc list
      kc list homelab
      export TOKEN=$(kc get homelab cloudflare-token)
    """)
    exit(0)
}

guard let command = argv.first else { usage() }

// Strip flags, leaving only positional args
let flags    = Set(argv.dropFirst().filter { $0.hasPrefix("--") })
let positional = argv.dropFirst().filter { !$0.hasPrefix("--") }
let wantsJSON = flags.contains("--json")

switch command {

// MARK: set
case "set":
    guard positional.count >= 2 else {
        fail("usage: kc set <service> <account>")
    }
    let service = positional[0], account = positional[1]
    guard let value = readSecret(prompt: "Secret for \(service)/\(account): "),
          !value.isEmpty else {
        fail("secret cannot be empty")
    }
    do {
        try Keychain.set(service: service, account: account, value: value)
        print("✓ Stored \(service)/\(account) — syncing via iCloud Keychain")
    } catch KeychainError.duplicateItem {
        fail("\(service)/\(account) already exists. Use `kc update \(service) \(account)` to overwrite.")
    } catch let e as KeychainError {
        fail(e.message)
    }

// MARK: get
case "get":
    guard positional.count >= 2 else {
        fail("usage: kc get <service> <account> [--json]")
    }
    let service = positional[0], account = positional[1]
    do {
        let value = try Keychain.get(service: service, account: account)
        if wantsJSON {
            printJSONValue(service: service, account: account, value: value)
        } else {
            print(value)
        }
    } catch KeychainError.notFound {
        fail("not found: \(service)/\(account)")
    } catch let e as KeychainError {
        fail(e.message)
    }

// MARK: update
case "update":
    guard positional.count >= 2 else {
        fail("usage: kc update <service> <account>")
    }
    let service = positional[0], account = positional[1]
    guard let value = readSecret(prompt: "New secret for \(service)/\(account): "),
          !value.isEmpty else {
        fail("secret cannot be empty")
    }
    do {
        try Keychain.update(service: service, account: account, value: value)
        print("✓ Updated \(service)/\(account)")
    } catch KeychainError.notFound {
        fail("not found: \(service)/\(account). Use `kc set \(service) \(account)` to create it.")
    } catch let e as KeychainError {
        fail(e.message)
    }

// MARK: delete
case "delete":
    guard positional.count >= 2 else {
        fail("usage: kc delete <service> <account>")
    }
    let service = positional[0], account = positional[1]
    guard confirm("Delete \(service)/\(account)? [y/N] ") else {
        print("Cancelled.")
        exit(0)
    }
    do {
        try Keychain.delete(service: service, account: account)
        print("✓ Deleted \(service)/\(account)")
    } catch KeychainError.notFound {
        fail("not found: \(service)/\(account)")
    } catch let e as KeychainError {
        fail(e.message)
    }

// MARK: list
case "list":
    let service: String? = positional.first
    do {
        let items = try Keychain.list(service: service)
        if items.isEmpty {
            let scope = service.map { " for service '\($0)'" } ?? ""
            print("No items stored\(scope).")
        } else if wantsJSON {
            printJSON(items)
        } else {
            printTable(items)
        }
    } catch let e as KeychainError {
        fail(e.message)
    }

default:
    fputs("error: unknown command '\(command)'\n\n", stderr)
    usage()
}
