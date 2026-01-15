# Skills Setup Guide

This document lists all setup steps needed for each Claude Code skill.

## Quick Reference

| Skill | Setup Required | Env Var(s) |
|-------|---------------|------------|
| alfred-clipboard | None | - |
| todoist | API token | `TODOIST_TOKEN` |
| linear | API key | `LINEAR_API_KEY` |
| datadog | API + App keys | `DD_API_KEY`, `DD_APP_KEY`, `DD_SITE` |
| airtable | Personal access token | `AIRTABLE_TOKEN` |
| google-calendar | gcloud CLI | `GOOGLE_QUOTA_PROJECT` |
| gmail | gcloud CLI | `GOOGLE_QUOTA_PROJECT` |
| google-drive | gcloud CLI | `GOOGLE_QUOTA_PROJECT` |

---

## No Setup Required

### alfred-clipboard
Works immediately - reads from `~/Library/Application Support/Alfred/Databases/clipboard.alfdb`

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

All Google skills use gcloud CLI for authentication. One-time setup for all three.

### Install gcloud CLI
```bash
brew install google-cloud-sdk
```

### Authenticate with required scopes
```bash
gcloud auth application-default login \
  --scopes="https://www.googleapis.com/auth/calendar.readonly,https://www.googleapis.com/auth/gmail.readonly,https://www.googleapis.com/auth/drive.readonly"
```

### Set quota project
You need a Google Cloud project with the Calendar, Gmail, and Drive APIs enabled.

```bash
gcloud auth application-default set-quota-project YOUR_PROJECT_ID
```

Add the quota project to your shell profile:
```bash
export GOOGLE_QUOTA_PROJECT="YOUR_PROJECT_ID"
```

Enable APIs if needed:
- https://console.developers.google.com/apis/api/calendar-json.googleapis.com/overview?project=YOUR_PROJECT_ID
- https://console.developers.google.com/apis/api/gmail.googleapis.com/overview?project=YOUR_PROJECT_ID
- https://console.developers.google.com/apis/api/drive.googleapis.com/overview?project=YOUR_PROJECT_ID

### How it works
The skills use `gcloud auth application-default print-access-token` to get a fresh access token. This auto-refreshes using the stored credentials.

**Important:** All Google API requests must include the quota project header:
```bash
-H "x-goog-user-project: ${GOOGLE_QUOTA_PROJECT}"
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
export GOOGLE_QUOTA_PROJECT="your-gcp-project-id"
```

Then reload: `source ~/.zshrc`

---

## Testing Skills

After setup, test each skill:

```bash
# Todoist
curl -s "https://api.todoist.com/rest/v2/projects" \
  -H "Authorization: Bearer ${TODOIST_TOKEN}" | jq '.[].name'

# Linear
curl -s -X POST "https://api.linear.app/graphql" \
  -H "Authorization: ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ viewer { name } }"}' | jq '.data.viewer.name'

# Datadog
curl -s "https://api.${DD_SITE}/api/v1/validate" \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -H "DD-APPLICATION-KEY: ${DD_APP_KEY}"

# Airtable
curl -s "https://api.airtable.com/v0/meta/bases" \
  -H "Authorization: Bearer ${AIRTABLE_TOKEN}" | jq '.bases[].name'

# Google (all three)
ACCESS_TOKEN=$(gcloud auth application-default print-access-token)

curl -s "https://www.googleapis.com/calendar/v3/users/me/calendarList" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "x-goog-user-project: ${GOOGLE_QUOTA_PROJECT}" | jq '.items[].summary'

curl -s "https://gmail.googleapis.com/gmail/v1/users/me/profile" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "x-goog-user-project: ${GOOGLE_QUOTA_PROJECT}"

curl -s "https://www.googleapis.com/drive/v3/files?pageSize=5" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "x-goog-user-project: ${GOOGLE_QUOTA_PROJECT}" | jq '.files[].name'

# Alfred Clipboard
sqlite3 ~/Library/Application\ Support/Alfred/Databases/clipboard.alfdb \
  "SELECT substr(item, 1, 50) FROM clipboard ORDER BY ts DESC LIMIT 5;"
```
