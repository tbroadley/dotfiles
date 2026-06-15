---
name: todoist
description: Manage tasks, projects, and productivity in Todoist. View tasks, add new items, check completed work, and organize projects.
---

# Todoist Task Management

This skill provides access to Todoist via the REST API (v1).

> **API version:** Use the **`/api/v1/`** endpoints. The older `/rest/v2/` (and
> `/sync/v9/`) endpoints are **deprecated** and now return a notice telling you to
> migrate to `/api/v1/` instead of data.

## Setup Required

**Get your API token:**

1. Go to Todoist Settings → Integrations → Developer
2. Or visit: https://todoist.com/app/settings/integrations/developer
3. Copy your API token

Set as environment variable:
```bash
export TODOIST_TOKEN="your-api-token"
```

## When to Use

Use this skill when the user:
- Asks about their tasks, TODOs, or what they need to do
- Wants to add a new task or reminder
- Asks about completed tasks or productivity
- Wants to organize projects or sections
- Mentions "Todoist" or their task list

## API Endpoints

Base URL: `https://api.todoist.com/api/v1`

All requests need:
```bash
-H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

**Important:** Use `$(printenv TODOIST_TOKEN)` to ensure the token expands correctly in all shell contexts (zsh eval can lose variable values).

### Response shape & pagination

List endpoints (`/tasks`, `/projects`, `/sections`, `/labels`, `/comments`, and
`/tasks/filter`) wrap results in a `results` array with a cursor, **not** a bare
JSON array like the old v2 API did:

```json
{ "results": [ ... ], "next_cursor": "abc123" }
```

- Page with `?limit=200&cursor=<next_cursor>`; keep fetching while `next_cursor`
  is non-null. Without a cursor you only get the first page.
- Access items as `.results[]` in `jq` (the v2-era `.[]` no longer works).

### ⚠️ Control characters in JSON (parsing gotcha)

The v1 API returns task `content`/`description` with **literal, unescaped control
characters** (raw newlines/tabs inside string values). This is technically
invalid JSON, so strict parsers reject it:

- `jq` fails with `Invalid string: control characters from U+0000 through U+001F must be escaped`.
- Python's `json.loads` fails with `Invalid control character at: ...`.

**Fix:** parse leniently in Python with `strict=False`. Prefer this over `curl | jq`
whenever you read task/comment text:

```python
import json, os, urllib.request

token = os.environ["TODOIST_TOKEN"]

def get(url):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    return json.loads(urllib.request.urlopen(req).read().decode(), strict=False)

# Fetch every task across all pages, then search.
tasks, cursor = [], None
while True:
    url = "https://api.todoist.com/api/v1/tasks?limit=200" + (f"&cursor={cursor}" if cursor else "")
    d = get(url)
    tasks += d["results"]
    cursor = d.get("next_cursor")
    if not cursor:
        break

for t in tasks:
    if "keyword" in t["content"].lower():
        print(t["id"], repr(t["content"]))
```

### Tasks

**Get All Tasks** (first page; paginate via `next_cursor`):
```bash
curl -s "https://api.todoist.com/api/v1/tasks?limit=200" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

**Get Tasks by Filter** (note: dedicated `/tasks/filter` endpoint with `query=`):
```bash
curl -s -G "https://api.todoist.com/api/v1/tasks/filter" \
  --data-urlencode "query=today" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

**Get Single Task**:
```bash
curl -s "https://api.todoist.com/api/v1/tasks/{TASK_ID}" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

**Create Task**:
```bash
curl -s -X POST "https://api.todoist.com/api/v1/tasks" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Task name",
    "due_string": "tomorrow",
    "priority": 2
  }'
```

**Complete Task** (returns `204 No Content`):
```bash
curl -s -X POST "https://api.todoist.com/api/v1/tasks/{TASK_ID}/close" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

### Projects

**Get All Projects**:
```bash
curl -s "https://api.todoist.com/api/v1/projects?limit=200" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

**Get Project**:
```bash
curl -s "https://api.todoist.com/api/v1/projects/{PROJECT_ID}" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

### Sections

**Get Sections**:
```bash
curl -s "https://api.todoist.com/api/v1/sections?limit=200" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

**Get Sections in Project**:
```bash
curl -s "https://api.todoist.com/api/v1/sections?project_id={PROJECT_ID}" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

### Labels

**Get All Labels**:
```bash
curl -s "https://api.todoist.com/api/v1/labels?limit=200" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

### Comments

**Get Comments on Task**:
```bash
curl -s "https://api.todoist.com/api/v1/comments?task_id={TASK_ID}" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

**Add Comment**:
```bash
curl -s -X POST "https://api.todoist.com/api/v1/comments" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)" \
  -H "Content-Type: application/json" \
  -d '{
    "task_id": "TASK_ID",
    "content": "Comment text"
  }'
```

## Filter Syntax

The `/tasks/filter` `query` parameter accepts Todoist filter syntax:

| Filter | Description |
|--------|-------------|
| `today` | Due today |
| `tomorrow` | Due tomorrow |
| `overdue` | Past due |
| `7 days` or `next 7 days` | Due in next 7 days |
| `no date` | No due date |
| `p1` | Priority 1 (urgent) |
| `@label_name` | Has label |
| `#project_name` | In project |
| `/section_name` | In section |
| `assigned to: me` | Assigned to you |
| `today & p1` | Combine with & |
| `today | tomorrow` | Combine with | (or) |

## Common Workflows

### Get Today's Tasks
```bash
curl -s -G "https://api.todoist.com/api/v1/tasks/filter" \
  --data-urlencode "query=today" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)" \
  | jq '.results[] | {content, due: .due.string, priority}'
```
(If `jq` errors on control characters, switch to the Python `strict=False` snippet above.)

### Get Overdue Tasks
```bash
curl -s -G "https://api.todoist.com/api/v1/tasks/filter" \
  --data-urlencode "query=overdue" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

### Add a Task for Tomorrow
```bash
curl -s -X POST "https://api.todoist.com/api/v1/tasks" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)" \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Review the PR",
    "due_string": "tomorrow",
    "priority": 2
  }'
```

### Get All Tasks in a Project
```bash
# First, find project ID
curl -s "https://api.todoist.com/api/v1/projects?limit=200" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)" | jq '.results[] | {name, id}'

# Then get tasks
curl -s "https://api.todoist.com/api/v1/tasks?project_id={PROJECT_ID}" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

### Get High Priority Tasks
```bash
curl -s -G "https://api.todoist.com/api/v1/tasks/filter" \
  --data-urlencode "query=p1 | p2" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)"
```

### List Projects with Task Counts
```bash
curl -s "https://api.todoist.com/api/v1/projects?limit=200" \
  -H "Authorization: Bearer $(printenv TODOIST_TOKEN)" | jq '.results[] | {name, id}'
```

## Task Properties

When creating tasks:
- **content**: Task text (required)
- **description**: Additional details
- **due_string**: Natural language date ("tomorrow", "every monday")
- **due_date**: Specific date (YYYY-MM-DD)
- **due_datetime**: With time (RFC3339)
- **priority**: 1 (urgent) to 4 (normal) - note: API uses 1=urgent, opposite of UI
- **project_id**: Project to add to
- **section_id**: Section within project
- **labels**: Array of label names
- **assignee_id**: For shared projects

## Notes

- Use the `/api/v1/` endpoints — `/rest/v2/` and `/sync/v9/` are deprecated.
- List responses are `{ "results": [...], "next_cursor": ... }`; paginate with `cursor`/`limit` and read `.results[]`.
- Task/comment text contains unescaped control characters — parse with Python `json.loads(..., strict=False)` if `jq` chokes.
- API rate limit: 1000 requests per 15 minutes per user
- Priority in API: 1 = urgent (p1 in UI), 4 = normal
- Due strings support natural language in multiple languages
- Get your token at: https://todoist.com/app/settings/integrations/developer

## Sources

- [Todoist API Reference (v1)](https://developer.todoist.com/api/v1/)
- [Find your API token](https://www.todoist.com/help/articles/find-your-api-token-Jpzx9IIlB)
