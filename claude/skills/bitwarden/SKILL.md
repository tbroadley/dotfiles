---
name: bitwarden
description: Access secrets and credentials from Bitwarden vault. Search items, get passwords, API keys, SSH keys, and secure notes.
---

# Bitwarden Vault Access

This skill provides access to the Bitwarden vault via the `bw` CLI.

## Setup Required

**Install the CLI:**
```bash
brew install bitwarden-cli
```

**Login and unlock:**
```bash
bw login           # One-time login with email + master password
bw unlock          # Returns a BW_SESSION token
```

**Session token** must be set as environment variable:
```bash
export BW_SESSION="..."
```

This is configured in `~/.zshrc.local`.

## When to Use

Use this skill when the user:
- Needs a secret, credential, API key, or password
- Asks to look up something in Bitwarden
- Needs SSH keys, tokens, or other sensitive values
- Is setting up a tool that requires credentials from the vault
- Mentions "Bitwarden" or "vault"

## CLI Commands

All commands require the session token. Use `--session "$(printenv BW_SESSION)"` or rely on the exported env var.

### Search for Items

```bash
bw list items --search "search term" --session "$(printenv BW_SESSION)" | \
  python3 -c "import sys,json; items=json.load(sys.stdin); [print(f'{i[\"name\"]} (id={i[\"id\"]})') for i in items]"
```

### Get Item Details

```bash
bw get item "ITEM_ID" --session "$(printenv BW_SESSION)" | \
  python3 -c "
import sys, json
item = json.load(sys.stdin)
print('Name:', item['name'])
if 'login' in item:
    print('Username:', item['login'].get('username', 'N/A'))
    print('Password:', item['login'].get('password', 'N/A'))
if 'fields' in item:
    for f in item['fields']:
        print(f'Field {f[\"name\"]}:', f.get('value', 'N/A'))
if 'notes' in item and item['notes']:
    print('Notes:', item['notes'])
"
```

### Get Just the Password

```bash
bw get password "ITEM_ID" --session "$(printenv BW_SESSION)"
```

### Get Just the Username

```bash
bw get username "ITEM_ID" --session "$(printenv BW_SESSION)"
```

### Get a Custom Field

```bash
bw get item "ITEM_ID" --session "$(printenv BW_SESSION)" | \
  python3 -c "import sys,json; item=json.load(sys.stdin); print(next(f['value'] for f in item.get('fields',[]) if f['name']=='FIELD_NAME'))"
```

### Get Notes

```bash
bw get notes "ITEM_ID" --session "$(printenv BW_SESSION)"
```

### List Items in a Folder

```bash
bw list items --folderid "FOLDER_ID" --session "$(printenv BW_SESSION)" | \
  python3 -c "import sys,json; [print(f'{i[\"name\"]} (id={i[\"id\"]})') for i in json.load(sys.stdin)]"
```

### List Folders

```bash
bw list folders --session "$(printenv BW_SESSION)" | \
  python3 -c "import sys,json; [print(f'{f[\"name\"]} (id={f[\"id\"]})') for f in json.load(sys.stdin)]"
```

### List Attachments

```bash
bw get item "ITEM_ID" --session "$(printenv BW_SESSION)" | \
  python3 -c "import sys,json; item=json.load(sys.stdin); [print(f'{a[\"fileName\"]} (id={a[\"id\"]})') for a in item.get('attachments',[])]"
```

### Download Attachment

```bash
bw get attachment "ATTACHMENT_ID" --itemid "ITEM_ID" --output /tmp/attachment --session "$(printenv BW_SESSION)"
```

## Item Types

Bitwarden items have a `type` field:
- `1` - Login (username/password)
- `2` - Secure Note
- `3` - Card
- `4` - Identity

## Common Workflows

### Find and Retrieve a Secret

```bash
# 1. Search for the item
bw list items --search "spacelift" --session "$(printenv BW_SESSION)" | \
  python3 -c "import sys,json; [print(f'{i[\"name\"]} (id={i[\"id\"]})') for i in json.load(sys.stdin)]"

# 2. Get the full item by ID
bw get item "ITEM_UUID" --session "$(printenv BW_SESSION)" | python3 -c "
import sys, json
item = json.load(sys.stdin)
print('Name:', item['name'])
if 'login' in item:
    print('Username:', item['login'].get('username', 'N/A'))
    print('Password:', item['login'].get('password', 'N/A'))
if 'fields' in item:
    for f in item['fields']:
        print(f'Field {f[\"name\"]}:', f.get('value', 'N/A'))
if 'notes' in item and item['notes']:
    print('Notes:', item['notes'])
"
```

### Export a Secret as Environment Variable

```bash
export MY_SECRET="$(bw get password 'ITEM_ID' --session "$(printenv BW_SESSION)")"
```

## Session Management

- Sessions expire after inactivity
- If you get `"You are not logged in"`, the session has expired
- Re-unlock with: `bw unlock` (user must run interactively)
- `bw status --session "$(printenv BW_SESSION)"` checks vault status
- `bw sync --session "$(printenv BW_SESSION)"` fetches latest vault data

## Notes

- Always use `$(printenv BW_SESSION)` to ensure the token expands correctly
- Search is case-insensitive and matches against item names
- Item IDs are UUIDs
- The `bw` CLI outputs JSON by default, use `python3` or `jq` to parse
- Never log or echo raw secrets to the terminal unnecessarily
- The vault is read-only in typical usage; creating/editing items requires additional permissions
