---
name: gws-gmail
description: "Read and search Gmail emails. Check inbox, search messages, and view email threads."
---

# Gmail via gws CLI

> See `../gws-shared/SKILL.md` for auth, global flags, and CLI syntax.

```bash
gws gmail <resource> <method> [flags]
```

## Quick Commands

### Unread inbox summary

```bash
gws gmail +triage
gws gmail +triage --max 5 --query 'from:boss'
gws gmail +triage --format json | jq '.[].subject'
```

### List messages

```bash
gws gmail users messages list --params '{"userId":"me","maxResults":10}'
gws gmail users messages list --params '{"userId":"me","q":"is:unread","maxResults":20}'
```

### Read a message

```bash
gws gmail users messages get --params '{"userId":"me","id":"MESSAGE_ID","format":"full"}'
gws gmail users messages get --params '{"userId":"me","id":"MESSAGE_ID","format":"metadata"}'
```

### Get a thread

```bash
gws gmail users threads get --params '{"userId":"me","id":"THREAD_ID","format":"full"}'
```

### Labels

```bash
gws gmail users labels list --params '{"userId":"me"}'
```

### Profile

```bash
gws gmail users getProfile --params '{"userId":"me"}'
```

## Gmail Search Query Syntax

Use the `q` parameter with Gmail search syntax:

| Query | Description |
|-------|-------------|
| `is:unread` | Unread messages |
| `is:starred` | Starred messages |
| `from:user@example.com` | From specific sender |
| `to:user@example.com` | To specific recipient |
| `subject:hello` | Subject contains "hello" |
| `has:attachment` | Has attachments |
| `filename:pdf` | Has PDF attachment |
| `after:2024/01/01` | After date |
| `before:2024/01/31` | Before date |
| `newer_than:7d` | Last 7 days |
| `older_than:1m` | Older than 1 month |
| `label:work` | Has label |
| `in:inbox` | In inbox |
| `in:sent` | In sent |

Combine queries: `from:boss@company.com subject:urgent after:2024/01/01`

## API Resources

- `users.getProfile`, `users.stop`, `users.watch`
- `users.drafts` — CRUD on drafts
- `users.history` — Mailbox change history
- `users.labels` — Label management
- `users.messages` — List, get, send, modify, trash, delete
- `users.settings` — Filters, forwarding, IMAP/POP, etc.
- `users.threads` — Thread operations

## Notes

- The `+triage` helper is read-only and never modifies your mailbox
- Message format options: `minimal`, `metadata`, `raw`, `full`
- The `snippet` field gives a preview without needing to decode the body
- Thread IDs group related messages together
