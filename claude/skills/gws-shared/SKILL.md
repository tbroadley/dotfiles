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

```bash
# In ~/.zshrc.local
export GOOGLE_WORKSPACE_CLI_CLIENT_ID="your-client-id"
export GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="your-client-secret"
```

```bash
# Login (opens browser for OAuth consent)
gws auth login

# Or select specific services to stay under scope limits (unverified apps cap at ~25 scopes)
gws auth login -s drive,gmail,calendar,sheets,docs
```

Re-login if you see `invalid_grant` errors (tokens expired):
```bash
gws auth login
```

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
