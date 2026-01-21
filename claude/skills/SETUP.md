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
| google-calendar | OAuth setup | - |
| gmail | OAuth setup | - |
| google-drive | OAuth setup | - |
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

---

## Google Services (Calendar, Gmail, Drive)

All Google skills use OAuth with a persistent refresh token. One-time setup for all three.

### Step 1: Create OAuth Client

1. Go to [Google Cloud Console - Credentials](https://console.cloud.google.com/apis/credentials)
2. Select or create a project
3. Click **Create Credentials** → **OAuth client ID**
4. If prompted, configure the OAuth consent screen:
   - User Type: **External** (or Internal if using Workspace)
   - App name: "Claude Code" (or anything)
   - User support email: your email
   - Developer contact: your email
   - Scopes: skip for now
   - Test users: add your email
5. Back in Credentials, create OAuth client ID:
   - Application type: **Desktop app**
   - Name: "Claude Code"
6. Download the JSON file (click the download icon)

### Step 2: Enable APIs

Enable these APIs in your project:
- [Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com)
- [Gmail API](https://console.cloud.google.com/apis/library/gmail.googleapis.com)
- [Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com)

### Step 3: Run Setup

```bash
google-oauth-setup ~/Downloads/client_secret_*.json
```

This will:
1. Open your browser for authorization
2. Start a local server to capture the OAuth callback
3. Exchange the authorization code for tokens
4. Save credentials to `~/.config/google-oauth/credentials.json`

### How it works

The `google-oauth-token` script automatically refreshes access tokens using the stored refresh token. Tokens are cached for their validity period (~1 hour) to avoid unnecessary API calls.

```bash
ACCESS_TOKEN=$(google-oauth-token)
```

The refresh token persists indefinitely unless you revoke it, so you won't need to re-authenticate.

### Troubleshooting

Check status:
```bash
google-oauth-setup --status
```

If you see "Token has been expired or revoked", re-run the setup:
```bash
google-oauth-setup ~/Downloads/client_secret_*.json
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

Note: Google credentials are stored in `~/.config/google-oauth/credentials.json` (not as environment variables).

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

# Google (all three)
ACCESS_TOKEN=$(google-oauth-token)

curl -s "https://www.googleapis.com/calendar/v3/users/me/calendarList" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq '.items[].summary'

curl -s "https://gmail.googleapis.com/gmail/v1/users/me/profile" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

curl -s "https://www.googleapis.com/drive/v3/files?pageSize=5" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq '.files[].name'

# Alfred Clipboard
sqlite3 ~/Library/Application\ Support/Alfred/Databases/clipboard.alfdb \
  "SELECT substr(item, 1, 50) FROM clipboard ORDER BY ts DESC LIMIT 5;"
```
