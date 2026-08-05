---
name: gws-shared
description: "gws CLI: Shared patterns for authentication, global flags, and output formatting."
---

# gws — Shared Reference

## Installation

```bash
npm install -g @googleworkspace/cli
```

## Authentication

`gws auth setup` cannot automatically create OAuth clients. Instead, create one manually in the
[Google Cloud Console](https://console.cloud.google.com/apis/credentials?project=metr-pub)
(Desktop app type), then set the env vars and login:

`GOOGLE_WORKSPACE_CLI_CLIENT_ID` is set in `~/.zshrc.local`.
`GOOGLE_WORKSPACE_CLI_CLIENT_SECRET` comes from Bitwarden on demand — run
`secrets-load` (see `~/dotfiles/secrets.zsh`) if it's unset. Neither is stored in a
tracked file.

```bash
# Login (opens browser for OAuth consent)
gws auth login

# Or select specific services to stay under scope limits (unverified apps cap at ~25 scopes)
gws auth login -s drive,gmail,calendar,sheets,docs
```

`gws auth login` shows an **interactive scope picker before** opening the browser, so it
needs a real TTY. Don't run it backgrounded or from a non-interactive shell — it will
hang silently on the picker with no output and no browser. Pass `-s <services>`,
`--readonly` or `--scopes` to skip the picker.

Re-login if you see `invalid_grant` errors (tokens expired):
```bash
gws auth login
```

### Other auth subcommands

| Command | Description |
|---------|-------------|
| `gws auth status` | Current auth state, credential source, keyring backend |
| `gws auth export` | Print decrypted credentials to stdout (a live refresh token — don't redirect to a file or paste it anywhere) |
| `gws auth logout` | Clear saved credentials and token cache |

### How credentials are stored

`~/.config/gws/credentials.enc` holds the refresh token, encrypted with AES-256-GCM.
The 256-bit key lives in the **macOS Keychain** (service `gws-cli`, account `$USER`).

Requires **>= 0.12.0**: earlier versions compiled only the keyring crate's in-memory
mock backend and silently fell back to a plaintext-adjacent `~/.config/gws/.encryption_key`
file sitting next to the ciphertext it protects. If `.encryption_key` exists, the
keyring isn't being used.

Note that upgrading does **not** migrate an existing file key into the keyring, despite
what the changelog implies — on an empty keyring the CLI generates a *new* key, which
makes the old `credentials.enc` undecryptable and forces a re-login. Expect to
re-authenticate after any upgrade that first enables the keyring.

`GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file` forces the old file behaviour — useful in
Docker or other keyring-less environments, but avoid it on a workstation.

## Global Flags

| Flag | Description |
|------|-------------|
| `--format <FORMAT>` | Output format: `json` (default), `table`, `yaml`, `csv` |
| `--dry-run` | Validate locally without calling the API |

## CLI Syntax

```bash
gws <service> <resource> [sub-resource] <method> [flags]
```

### Method Flags

| Flag | Description |
|------|-------------|
| `--params '{"key": "val"}'` | URL/query parameters |
| `--json '{"key": "val"}'` | Request body |
| `-o, --output <PATH>` | Save binary responses to file |
| `--upload <PATH>` | Upload file content (multipart) |
| `--page-all` | Auto-paginate (NDJSON output) |
| `--page-limit <N>` | Max pages when using --page-all (default: 10) |
| `--page-delay <MS>` | Delay between pages in ms (default: 100) |

## Discovering Commands

```bash
# Browse resources and methods
gws <service> --help

# Inspect a method's required params, types, and defaults
gws schema <service>.<resource>.<method>
```

Use `gws schema` output to build your `--params` and `--json` flags.
