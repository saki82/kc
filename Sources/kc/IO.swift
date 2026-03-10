import Foundation

#if canImport(Darwin)
import Darwin
#endif

// MARK: - Secure input

/// Reads a line from stdin with echo disabled — value never appears in terminal
/// or shell history. Restores terminal state even on interrupt.
func readSecret(prompt: String) -> String? {
    print(prompt, terminator: "")
    fflush(stdout)

    var original = termios()
    tcgetattr(STDIN_FILENO, &original)

    var silent = original
    silent.c_lflag &= ~tcflag_t(ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &silent)

    let value = readLine(strippingNewline: true)

    tcsetattr(STDIN_FILENO, TCSANOW, &original)
    print() // newline after hidden input

    return value
}

/// Reads a plain confirmation line.
func confirm(_ prompt: String) -> Bool {
    print(prompt, terminator: "")
    fflush(stdout)
    return readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "y"
}

// MARK: - Output

func printFieldTable(service: String, account: String, payload: SecretPayload) {
    let fieldW = max(payload.sortedKeys.map { $0.count }.max() ?? 0, 5)
    let header  = "FIELD".padding(toLength: fieldW, withPad: " ", startingAt: 0) + "  VALUE"
    let divider = String(repeating: "─", count: fieldW + 2 + 20)
    print("\(service)/\(account)")
    print(header)
    print(divider)
    for key in payload.sortedKeys {
        let k = key.padding(toLength: fieldW, withPad: " ", startingAt: 0)
        print("\(k)  \(payload.fields[key] ?? "")")
    }
}

func printFieldJSON(service: String, account: String, payload: SecretPayload) {
    let pairs = payload.sortedKeys
        .map { "\"" + $0 + "\":\"" + (payload.fields[$0] ?? "").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        .joined(separator: ",")
    print("{\"service\":\"\(service)\",\"account\":\"\(account)\",\(pairs)}")
}

func printTable(_ entries: [SecretEntry]) {
    guard !entries.isEmpty else { return }
    let svcW = max(entries.map { $0.service.count }.max() ?? 0, 7)
    let accW = max(entries.map { $0.account.count }.max() ?? 0, 7)

    let header  = "SERVICE".padding(toLength: svcW, withPad: " ", startingAt: 0)
               + "  "
               + "ACCOUNT"
    let divider = String(repeating: "─", count: svcW + 2 + accW)

    print(header)
    print(divider)
    for e in entries {
        let svc = e.service.padding(toLength: svcW, withPad: " ", startingAt: 0)
        print("\(svc)  \(e.account)")
    }
}

func printJSON(_ entries: [SecretEntry]) {
    let rows = entries.map { "{\"service\":\"\($0.service)\",\"account\":\"\($0.account)\"}" }
    print("[\(rows.joined(separator: ","))]")
}

func printJSONValue(service: String, account: String, value: String) {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
    print("{\"service\":\"\(service)\",\"account\":\"\(account)\",\"value\":\"\(escaped)\"}")
}

// MARK: - Error exit

func fail(_ message: String, code: Int32 = 1) -> Never {
    fputs("error: \(message)\n", stderr)
    exit(code)
}
