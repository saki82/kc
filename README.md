# kc

**Encrypted secret store for macOS, synced via iCloud Drive.**

Store API keys, tokens, and multi-field credentials — encrypted on disk, synced automatically across all your Macs. No third-party accounts, no cloud services beyond iCloud, no vendor lock-in.

```
kc set    aws production       # store credentials (interactive, never in shell history)
kc get    aws production       # retrieve all fields
kc get    aws production secret-key  # retrieve one field, raw and pipeable
```

---

## Why kc

Most secrets management options for developers involve a trade-off:

- **Password managers** (1Password, Bitwarden) are optimised for website logins, not structured API credentials
- **Cloud vaults** (Doppler, HashiCorp Vault) require third-party accounts and ongoing service dependency
- **`.env` files** leak into git history and don't roam between machines
- **macOS Keychain CLI** (`security`) writes local-only items — nothing syncs

`kc` uses infrastructure you already have: iCloud Drive for sync, the macOS Security framework for local passphrase storage, and CryptoKit for encryption. No new accounts. No subscriptions. No servers.

---

## How it works

Secrets are stored as AES-256-GCM encrypted files:

```
iCloud Drive/
└── kc/
    ├── .salt                    ← random salt (syncs, not secret)
    ├── aws/
    │   └── production           ← encrypted: {access-key, secret-key, region}
    ├── stripe/
    │   └── live                 ← encrypted: {secret-key, webhook-secret}
    └── github/
        └── token                ← encrypted: {value}
```

- **File names** are visible in Finder. Values are not.
- **Master passphrase** lives only in your head and in the local login Keychain. Never leaves the machine, never syncs.
- **Same passphrase + same salt = same key** on every machine. Run `kc init` once per machine, enter your passphrase — all secrets are immediately accessible.

---

## Install

**Homebrew (recommended):**
```bash
brew tap saki82/kc
brew install kc
```

**From source:**
```bash
git clone https://github.com/saki82/kc.git
cd kc
swift build -c release
mkdir -p ~/.local/bin && cp .build/release/kc ~/.local/bin/kc
```

Requires macOS 13+ and Swift 5.9+ (`xcode-select --install`).

---

## Setup

```bash
kc init
```

- **First machine:** generates a random salt, creates the vault in iCloud Drive, prompts for a passphrase (with confirmation), stores it in the local login Keychain.
- **New machine:** detects the existing vault in iCloud Drive, prompts for your passphrase (no confirmation), stores it locally. All secrets are immediately readable.

---

## Usage

```
kc init                                  First-time setup or restore on a new machine
kc set    <service> <account>            Store a secret
kc get    <service> <account> [field]    Retrieve all fields or one raw value
kc update <service> <account> [field]    Update a field
kc import <service> <account> <file>     Import from a .env file
kc delete <service> <account> [field]    Delete a field or entire secret
kc list   [<service>]        [--json]    List secrets — values never shown
kc -h                                    Show help
```

### Single-value secrets

Press Enter at the first field prompt:

```
$ kc set github token
Field name (Enter = single value): ↵
Secret: ••••••••
✓ Stored github/token
```

```bash
kc get github token                  # prints raw value
export GH_TOKEN=$(kc get github token)
```

### Multi-field secrets

Type field names, press Enter with no input to finish:

```
$ kc set aws production
Field name (Enter = single value): access-key
Value for 'access-key': ••••••••••••••••••••
Field name (Enter to finish): secret-key
Value for 'secret-key': ••••••••••••••••••••••••••••••••••••••••
Field name (Enter to finish): region
Value for 'region': ••••••••••
Field name (Enter to finish): ↵
✓ Stored aws/production (3 fields: access-key, region, secret-key)
```

```bash
kc get aws production                # table of all fields
kc get aws production secret-key     # raw value, pipeable
kc update aws production secret-key  # replace one field
kc delete aws production region      # remove one field
kc delete aws production             # remove entire secret
```

---

## Migrating from .env files

```bash
kc import aws production .env.production
```

Parses `KEY=value` pairs (skips comments and blank lines, strips `export` prefix and surrounding quotes), shows a preview, and asks for confirmation before writing. Field names are preserved exactly as-is.

```
Importing 3 field(s) into aws/production:

  FIELD             VALUE
  ──────────────────────────────
  AWS_ACCESS_KEY_ID   AKIA...
  AWS_REGION          eu-central-1
  AWS_SECRET_ACCESS_KEY  wJalr...

Import into aws/production? [y/N]
```

Fails if `aws/production` already exists — use `kc update` to modify individual fields after import.

**Migrating from shell profiles** (`.zshrc`, `.zshenv`): extract `export KEY=value` lines into a temporary `.env` file, run `kc import`, then replace the hardcoded values in your profile with `$(kc get ...)` calls.

**Migrating from password managers**: export to CSV, then use `kc set` interactively — CSV schemas vary too much per app to import reliably.

---

## Shell integration

```bash
# Inline injection
AWS_SECRET=$(kc get aws production secret-key) your-command

# Shell profile — resolved silently after init, no prompt
export STRIPE_SECRET_KEY=$(kc get stripe live secret-key)
```

### direnv (recommended for project-level secrets)

[direnv](https://direnv.net) executes `.envrc` as a shell script when you `cd` into a directory, injecting secrets as env vars before your process starts. Unlike `.env` files, command substitution works.

```bash
brew install direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc  # or ~/.bash_profile
```

Add an `.envrc` to your project root:

```bash
# .envrc — add to .gitignore, never commit
export STRIPE_SECRET_KEY=$(kc get stripe live secret-key)
export STRIPE_WEBHOOK_SECRET=$(kc get stripe live webhook-secret)
export AWS_ACCESS_KEY_ID=$(kc get aws production access-key)
export AWS_SECRET_ACCESS_KEY=$(kc get aws production secret-key)
```

```bash
direnv allow   # run once per project to whitelist the .envrc
```

From that point on, `cd` into the project and secrets are live. Your TypeScript, Go, or Python process reads them via `process.env` / `os.Getenv` / `os.environ` — no dotenv library needed, no `.env` files in the repo.

> **Why not `.env` files?** Dotenv parsers are not shells — `$(...)` is never evaluated. The literal string `$(kc get stripe live secret-key)` would be passed to your app. `.envrc` + direnv is the correct layer for dynamic secret injection.

### Scripting and automation

Set `KC_PASSPHRASE` in the environment to bypass all interactive prompts:

```bash
export KC_PASSPHRASE=$(security find-generic-password -a passphrase -s kc -w)
kc get stripe live secret-key
```

---

## Security

| What | Mechanism |
|---|---|
| Encryption | AES-256-GCM — authenticated, tamper-evident |
| Key derivation | PBKDF2-SHA256, 200,000 iterations |
| Passphrase storage | macOS login Keychain (local only, never synced) |
| Sync transport | iCloud Drive (Apple infrastructure) |
| Shell history | Secrets are never CLI arguments — always hidden prompt or env var |

An attacker with access to your iCloud Drive sees encrypted blobs and file names — no values. An attacker with access to your Mac sees the passphrase in the login Keychain and the encrypted files — values are exposed only with both.

---

## Requirements

- macOS 13 (Ventura) or later
- iCloud Drive enabled — System Settings → Apple ID → iCloud → Drive

---

## License

MIT
