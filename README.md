# kc — iCloud Keychain CLI

A minimal Swift CLI that wraps the macOS Security framework with `kSecAttrSynchronizable: true`.  
Every secret you store automatically syncs across all your Apple devices via iCloud Keychain.

No third-party dependencies. Single binary. Zero external services.

---

## Why

The built-in `security` CLI cannot set `kSecAttrSynchronizable`, so items it writes stay local.  
`kc` fixes that: everything it stores syncs. Get a new Mac, sign into iCloud — your secrets are there.

---

## Install

```bash
git clone https://github.com/<you>/kc.git
cd kc
swift build -c release
cp .build/release/kc /usr/local/bin/kc
```

On a new machine, this is all you need. Secrets are already there via iCloud.

---

## Usage

```bash
kc set    <service> <account>           # store — prompts securely, no shell history
kc get    <service> <account>           # retrieve — raw value, pipeable
kc update <service> <account>           # overwrite existing
kc delete <service> <account>           # delete with confirmation
kc list   [<service>]        [--json]   # list items — never shows values
kc get    <service> <account> --json    # structured output
```

### Naming convention

| `service`   | `account`              |
|-------------|------------------------|
| `homelab`   | `cloudflare-token`     |
| `homelab`   | `fastapi-bearer`       |
| `bizpulse`  | `stripe-secret-key`    |
| `bizpulse`  | `shopify-api-key`      |
| `openai`    | `api-key`              |

`service` = logical group. `account` = specific key within that group.

---

## Shell integration

### Inline injection
```bash
CLOUDFLARE_TOKEN=$(kc get homelab cloudflare-token) some-command
```

### Export in shell profile
```bash
# ~/.zshrc or ~/.zshenv — loaded on demand, not hardcoded
export CLOUDFLARE_API_TOKEN=$(kc get homelab cloudflare-token)
```

> **Note:** This triggers a Keychain auth prompt once per session on first access.
> Subsequent calls in the same session are cached by the OS.

### direnv per-project (.envrc)
```bash
# .envrc
export STRIPE_SECRET_KEY=$(kc get bizpulse stripe-secret-key)
export SHOPIFY_API_KEY=$(kc get bizpulse shopify-api-key)
```
Add `.envrc` to `.gitignore`. Secrets load automatically on `cd` via `direnv`.

### Script usage
```bash
#!/bin/bash
API_KEY=$(kc get openai api-key) \
  curl -H "Authorization: Bearer $API_KEY" https://api.openai.com/v1/models
```

---

## Behaviour notes

- **iCloud sync:** Every write uses `kSecAttrSynchronizable: true`. Items appear on all signed-in devices within seconds.
- **Auth prompt:** First access per session triggers a macOS Touch ID / password dialog. Approve "Always Allow" to suppress future prompts for that item.
- **Shell history safe:** Secrets are never passed as CLI arguments — always via a hidden prompt.
- **Scoped to kc:** `kc list` only shows items created by `kc` (via `kSecAttrLabel`). Other keychain items are never touched.
- **Update promotes to sync:** If you have an old local-only item, `kc update` will mark it as synchronizable going forward.

---

## Requirements

- macOS 13+
- Swift 5.9+ (`xcode-select --install`)
- iCloud Keychain enabled (System Settings → Apple ID → iCloud → Passwords & Keychain)
