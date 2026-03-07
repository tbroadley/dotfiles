# Skills Setup Guide

This document lists all setup steps needed for each Claude Code skill.

## Quick Reference

| Skill | Setup Required | Env Var(s) |
|-------|---------------|------------|
| alfred-clipboard | None | - |
| learn | None | - |
| todoist | API token | `TODOIST_TOKEN` |
| linear | API key | `LINEAR_API_KEY` |
| datadog | API + App keys | `DD_API_KEY`, `DD_APP_KEY`, `DD_SITE` |
| airtable | Personal access token | `AIRTABLE_TOKEN` |
| bitwarden | CLI + vault login | `BW_SESSION` |
| gws-calendar | gws CLI + auth | `GOOGLE_WORKSPACE_CLI_CLIENT_ID`, `GOOGLE_WORKSPACE_CLI_CLIENT_SECRET` |
| gws-gmail | gws CLI + auth | `GOOGLE_WORKSPACE_CLI_CLIENT_ID`, `GOOGLE_WORKSPACE_CLI_CLIENT_SECRET` |
| gws-drive | gws CLI + auth | `GOOGLE_WORKSPACE_CLI_CLIENT_ID`, `GOOGLE_WORKSPACE_CLI_CLIENT_SECRET` |
| read-inspect-eval | Python package | `pip install inspect-ai` |
| download-inspect-eval | AWS CLI + profile | `AWS_PROFILE=production` |
| hawk-monitoring | hawk CLI | `pip install hawk-cli` |
| hawk-view-results | hawk CLI | `pip install hawk-cli` |

---

## No Setup Required

### alfred-clipboard
Works immediately - reads from `~/Library/Application Support/Alfred/Databases/clipboard.alfdb`

### learn
Works immediately - extracts learnings from conversations and updates ~/dotfiles/claude/CLAUDE.md

---

## Minimal Setup

### read-inspect-eval
Requires the `inspect-ai` Python package:
```bash
pip install inspect-ai
```

### download-inspect-eval
Requires AWS CLI with access to the production profile:
```bash
AWS_PROFILE=production aws s3 ls s3://production-metr-inspect-data/
```

### hawk-monitoring / hawk-view-results
Requires the `hawk` CLI:
```bash
pip install hawk-cli
```

---

## Quick Setup (API Token Only)

### todoist
1. Go to https://todoist.com/app/settings/integrations/developer
2. Copy your API token
3. Add to shell profile:
   ```bash
   export TODOIST_TOKEN="your-token-here"
   ```

### linear
1. Go to https://linear.app/settings/account/security
2. Under "Personal API keys", click "Create key"
3. Select permissions: Read, Write (and optionally Admin)
4. Select teams to grant access to
5. Add to shell profile:
   ```bash
   export LINEAR_API_KEY="lin_api_..."
   ```

### datadog
1. Go to Datadog → Organization Settings → API Keys
2. Create or copy an API Key
3. Go to Organization Settings → Application Keys
4. Create an Application Key
5. Add to shell profile:
   ```bash
   export DD_API_KEY="your-api-key"
   export DD_APP_KEY="your-application-key"
   export DD_SITE="us3.datadoghq.com"  # Your Datadog site
   ```

### airtable
1. Go to https://airtable.com/create/tokens
2. Click "Create new token"
3. Add scopes: `data.records:read`, `schema.bases:read`
4. Add access to the bases you want to query
5. Add to shell profile:
   ```bash
   export AIRTABLE_TOKEN="pat..."
   ```

### bitwarden
1. Install: `brew install bitwarden-cli`
2. Login: `bw login` (email + master password + 2FA)
3. Unlock: `bw unlock` (returns a session token)
4. Add to shell profile:
   ```bash
   export BW_SESSION="..."
   ```
5. Note: Session tokens expire after inactivity. Re-run `bw unlock` and update `BW_SESSION` when needed.

---

## Google Workspace (Calendar, Gmail, Drive, Docs, Sheets)

All Google skills use the `gws` CLI (`@googleworkspace/cli`). One-time setup for all services.

### Step 1: Install gws

```bash
npm install -g @googleworkspace/cli
```

### Step 2: Create OAuth Client

`gws auth setup` cannot automatically create OAuth clients. You must create one manually:

1. **Configure OAuth consent screen** (if not already done):
   https://console.cloud.google.com/apis/credentials/consent?project=metr-pub
   - User Type: External
   - App name: `gws CLI`
   - Support email: your email
   - Save and continue through all screens

2. **Create OAuth client ID**:
   https://console.cloud.google.com/apis/credentials?project=metr-pub
   - Click **Create Credentials → OAuth client ID**
   - Application type: **Desktop app**
   - Name: `gws CLI`
   - Copy the **Client ID** and **Client Secret**

### Step 3: Set Environment Variables and Login

Add to `~/.zshrc.local`:
```bash
export GOOGLE_WORKSPACE_CLI_CLIENT_ID="your-client-id"
export GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="your-client-secret"
```

Then login:
```bash
source ~/.zshrc.local
gws auth login
```

This opens a browser for OAuth consent. Once complete, tokens are stored in `~/.config/gws/`.

Note: If your OAuth app is unverified (testing mode), Google limits consent to ~25 scopes. Use `-s` to select specific services instead of the `recommended` preset:
```bash
gws auth login -s drive,gmail,calendar,sheets,docs
```

### Troubleshooting

Test that auth works:
```bash
gws drive files list --params '{"pageSize": 3}'
gws gmail users messages list --params '{"userId": "me", "maxResults": 3}'
gws calendar calendarList list --params '{"maxResults": 3}'
```

Re-login if tokens expire (you'll see `invalid_grant` errors):
```bash
gws auth login
```

---

## Adding Environment Variables

Add exports to your shell profile (`~/.zshrc` or `~/.bashrc`):

```bash
# Claude Code Skills
export TODOIST_TOKEN="..."
export LINEAR_API_KEY="..."
export DD_API_KEY="..."
export DD_APP_KEY="..."
export DD_SITE="us3.datadoghq.com"
export AIRTABLE_TOKEN="..."
```

export GOOGLE_WORKSPACE_CLI_CLIENT_ID="..."
export GOOGLE_WORKSPACE_CLI_CLIENT_SECRET="..."

Note: OAuth tokens are managed by `gws` CLI (stored in `~/.config/gws/`).

Then reload: `source ~/.zshrc`

---

## Testing Skills

After setup, test each skill:

```bash
# Todoist
curl -s "https://api.todoist.com/rest/v2/projects" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)" | jq '.[].name'

# Linear
curl -s -X POST "https://api.linear.app/graphql" \
  -H "Authorization: $(printenv LINEAR_API_KEY)" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ viewer { name } }"}' | jq '.data.viewer.name'

# Datadog
curl -s "https://api.$(printenv DD_SITE)/api/v1/validate" \
  -H "DD-API-KEY: $(printenv DD_API_KEY)" \
  -H "DD-APPLICATION-KEY: $(printenv DD_APP_KEY)"

# Airtable
curl -s "https://api.airtable.com/v0/meta/bases" \
  -H "Authorization: Bearer $(printenv AIRTABLE_TOKEN)" | jq '.bases[].name'

# Google Workspace (all services via gws CLI)
gws calendar +agenda --today
gws gmail +triage --max 3
gws drive files list --params '{"pageSize": 5}'

# Bitwarden
bw status --session "$(printenv BW_SESSION)" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])"

# Alfred Clipboard
sqlite3 ~/Library/Application\ Support/Alfred/Databases/clipboard.alfdb \
  "SELECT substr(item, 1, 50) FROM clipboard ORDER BY ts DESC LIMIT 5;"
```
