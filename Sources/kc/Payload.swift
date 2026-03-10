import Foundation

// SecretPayload is the internal model for every secret file.
// On disk: AES-256-GCM encrypted JSON  →  {"api-key": "...", "api-secret": "..."}
// Single-value secrets use the reserved field name "value".
// Legacy plain-string files (pre-structured format) are transparently promoted.

struct SecretPayload {
    var fields: [String: String]

    // MARK: - Direct init (from field dict, used in kc set)

    init(fields: [String: String]) {
        self.fields = fields
    }

    // MARK: - Deserialise (decrypt result → model)

    init(from plaintext: String) {
        if let data = plaintext.data(using: .utf8),
           let json = try? JSONDecoder().decode([String: String].self, from: data) {
            self.fields = json
        } else {
            // Legacy: plain string → wrap as single-value
            self.fields = ["value": plaintext]
        }
    }

    // MARK: - Serialise (model → encrypt input)

    func serialised() throws -> String {
        let data = try JSONEncoder().encode(fields)
        guard let string = String(data: data, encoding: .utf8) else {
            throw PayloadError.serialisationFailed
        }
        return string
    }

    // MARK: - Helpers

    /// True when the payload holds exactly one field named "value" — simple scalar secret.
    var isSingleValue: Bool {
        fields.count == 1 && fields["value"] != nil
    }

    var sortedKeys: [String] {
        fields.keys.sorted()
    }
}

enum PayloadError: Error {
    case serialisationFailed
    case fieldNotFound(String)

    var message: String {
        switch self {
        case .serialisationFailed:     return "failed to serialise secret payload"
        case .fieldNotFound(let f):    return "field '\(f)' not found"
        }
    }
}
