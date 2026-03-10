# kc — encrypted secret store synced via iCloud Drive

A minimal Swift CLI that stores secrets as AES-256-GCM encrypted files in iCloud Drive.
Syncs automatically across all your Apple devices. No entitlements, no App Store, no cloud services.

No third-party dependencies. Single binary.

---

## How it works

```
iCloud Drive/kc/
├── .salt                         ← random 32-byte salt (not secret, syncs via iCloud)
├── homelab/
│   ├── cloudflare-token          ← encrypted single-value secret
│   └── shopify                   ← encrypted multi-field secret (api-key, api-secret, ...)
└── bizpulse/
    └── stripe                    ← encrypted multi-field secret

Local login Keychain (per machine, never synced):
└── kc/passphrase                 ← your master passphrase
```

- **File names** (`service/account`) are visible in Finder — values are never exposed
- **Passphrase** lives only in your head and in the local Keychain. Never synced.
- **Salt** syncs via iCloud Drive. Same passphrase + same salt = same key on every machine.
- **Scripting**: set `KC_PASSPHRASE` in the environment to bypass Keychain entirely

---

## Install

```bash
git clone https://github.com/<you>/kc.git
cd kc
swift build -c release
mkdir -p ~/.local/bin
cp .build/release/kc ~/.local/bin/kc
```

`~/.local/bin` is the XDG-standard location for user-scoped binaries — no `sudo`, no package manager.

Ensure it is on your PATH (add to `~/.zshrc` if not already there):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## Setup

### First machine

```bash
kc init
# → generates salt, saves to iCloud Drive/kc/.salt
# → prompts for master passphrase (with confirmation)
# → stores passphrase in local login Keychain
# → vault is ready and will sync automatically
```

### New machine (restore)

```bash
# 1. Clone, build, install binary as above
# 2. Run:
kc init
# → detects existing salt in iCloud Drive → restore mode
# → prompts for master passphrase (no confirmation needed)
# → stores passphrase in local Keychain
# → all existing secrets immediately readable
```

---

## Usage

```
kc set    <service> <account>              Store a secret (interactive field loop)
kc get    <service> <account> [field]      Show all fields, or retrieve one raw value
kc update <service> <account> [field]      Update a field (or the single value)
kc delete <service> <account> [field]      Delete a field or the entire secret
kc list   [<service>]        [--json]      List stored secrets — never shows values
kc -h                                      Show this help
```

---

## Single-value secrets

Press Enter at the first field prompt to store a simple scalar secret:

```
kc set homelab cloudflare-token

Field name (Enter = single value): ↵
Secret: ••••••••
✓ Stored homelab/cloudflare-token
```

Retrieve:
```bash
kc get homelab cloudflare-token          # prints raw value
export TOKEN=$(kc get homelab cloudflare-token)
```

---

## Multi-field secrets

Type field names at the prompt. Enter with no input to finish:

```
kc set homelab shopify

Field name (Enter = single value): api-key
Value for 'api-key': ••••••••
Field name (Enter to finish): api-secret
Value for 'api-secret': ••••••••
Field name (Enter to finish): endpoint
Value for 'endpoint': ••••••••
Field name (Enter to finish): ↵
✓ Stored homelab/shopify (3 fields: api-key, api-secret, endpoint)
```

Retrieve all fields (table):
```
kc get homelab shopify

homelab/shopify
FIELD       VALUE
───────────────────────────────
api-key     sk_live_...
api-secret  whsec_...
endpoint    https://...
```

Retrieve one field (raw, pipeable):
```bash
kc get homelab shopify api-key
export SHOPIFY_KEY=$(kc get homelab shopify api-key)
```

Update a single field without touching the others:
```bash
kc update homelab shopify api-secret
```

Remove a single field:
```bash
kc delete homelab shopify endpoint
```

Remove the entire secret:
```bash
kc delete homelab shopify
```

---

## Naming convention

| `service`   | `account`         | Fields                              |
|-------------|-------------------|-------------------------------------|
| `homelab`   | `cloudflare`      | `token`                             |
| `homelab`   | `shopify`         | `api-key`, `api-secret`, `endpoint` |
| `bizpulse`  | `stripe`          | `secret-key`, `webhook-secret`      |
| `openai`    | `default`         | *(single value)*                    |

`service` = logical group. `account` = credential set within that group.

---

## Shell integration

### Inline injection
```bash
CLOUDFLARE_TOKEN=$(kc get homelab cloudflare-token) some-command
```

### Shell profile
```bash
# ~/.zshrc — resolved silently from local Keychain, no prompt after init
export CLOUDFLARE_API_TOKEN=$(kc get homelab cloudflare-token)
```

### direnv per-project (.envrc)
```bash
export STRIPE_SECRET_KEY=$(kc get bizpulse stripe secret-key)
export STRIPE_WEBHOOK=$(kc get bizpulse stripe webhook-secret)
```
Add `.envrc` to `.gitignore`. Secrets load on `cd` via `direnv`.

### Scripting / automation (no prompts)
```bash
export KC_PASSPHRASE=$(security find-generic-password -a passphrase -s kc -w)
kc get homelab cloudflare-token
```

---

## Security notes

- **Encryption:** AES-256-GCM — authenticated, tampering is detected on decrypt
- **Key derivation:** PBKDF2-SHA256, 200k iterations — brute-force resistant
- **iCloud exposure:** encrypted blobs and file names only. No values.
- **Local exposure:** passphrase in login Keychain + encrypted files. Values readable only with both.
- **Shell history:** secrets are never passed as CLI arguments — always via hidden prompt or env var

---

## Requirements

- macOS 13+
- Swift 5.9+ (`xcode-select --install`)
- iCloud Drive enabled (System Settings → Apple ID → iCloud → Drive)
