---
name: gws-drive
description: "Search and read Google Drive files, Google Docs, Sheets, and Slides."
---

# Google Drive & Docs via gws CLI

> See `../gws-shared/SKILL.md` for auth, global flags, and CLI syntax.

```bash
gws drive <resource> <method> [flags]
gws docs <resource> <method> [flags]
gws sheets <resource> <method> [flags]
```

## Drive — File Operations

### List recent files

```bash
gws drive files list --params '{
  "pageSize": 20,
  "orderBy": "modifiedTime desc",
  "includeItemsFromAllDrives": true,
  "supportsAllDrives": true,
  "corpora": "allDrives"
}'
```

### Search files

```bash
gws drive files list --params '{
  "q": "name contains '\''meeting notes'\''",
  "pageSize": 20,
  "includeItemsFromAllDrives": true,
  "supportsAllDrives": true,
  "corpora": "allDrives"
}'
```

### Get file metadata

```bash
gws drive files get --params '{"fileId": "FILE_ID", "fields": "*", "supportsAllDrives": true}'
```

### Export Google Doc as text

```bash
gws drive files export --params '{"fileId": "FILE_ID", "mimeType": "text/plain"}'
```

### Upload a file

```bash
gws drive +upload --file /path/to/file.pdf
```

## Docs

### Get document content

```bash
gws docs documents get --params '{"documentId": "DOC_ID"}'
```

### Create a blank document

```bash
gws docs documents create --json '{"title": "My Document"}'
```

### Append text to a document

```bash
gws docs +write --doc DOC_ID --text "Hello, world"
```

## Sheets

### Read sheet values

```bash
gws sheets +read --spreadsheet SHEET_ID --range 'Sheet1!A1:D10'
gws sheets +read --spreadsheet SHEET_ID --range Sheet1
```

### Get spreadsheet metadata

```bash
gws sheets spreadsheets get --params '{"spreadsheetId": "SHEET_ID"}'
```

## Search Query Syntax

The `q` parameter in `drive files list` uses Drive search syntax:

| Query | Description |
|-------|-------------|
| `name contains 'report'` | Name contains text |
| `name = 'Exact Name'` | Exact name match |
| `fullText contains 'search term'` | Content contains text |
| `mimeType = 'application/vnd.google-apps.document'` | Google Docs |
| `mimeType = 'application/vnd.google-apps.spreadsheet'` | Google Sheets |
| `mimeType = 'application/pdf'` | PDF files |
| `modifiedTime > '2024-01-01'` | Modified after date |
| `'folder_id' in parents` | Files in specific folder |
| `starred = true` | Starred files |
| `trashed = false` | Not in trash |

Combine with `and`/`or`: `name contains 'meeting' and mimeType = 'application/vnd.google-apps.document'`

## MIME Types

| Type | MIME Type |
|------|-----------|
| Google Doc | `application/vnd.google-apps.document` |
| Google Sheet | `application/vnd.google-apps.spreadsheet` |
| Google Slides | `application/vnd.google-apps.presentation` |
| Google Form | `application/vnd.google-apps.form` |
| Folder | `application/vnd.google-apps.folder` |

## Export Formats

| Original | Export MIME Types |
|----------|------------------|
| Document | `text/plain`, `text/html`, `application/pdf`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document` |
| Spreadsheet | `text/csv`, `application/pdf`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` |
| Presentation | `application/pdf`, `text/plain` |

## Extracting File IDs from URLs

- Doc: `https://docs.google.com/document/d/{FILE_ID}/edit`
- Sheet: `https://docs.google.com/spreadsheets/d/{FILE_ID}/edit`
- Drive: `https://drive.google.com/file/d/{FILE_ID}/view`

## Revision History

```bash
# List revisions
gws drive revisions list --params '{"fileId": "DOC_ID", "fields": "revisions(id,modifiedTime,lastModifyingUser)"}'

# Get a specific revision
gws drive revisions get --params '{"fileId": "DOC_ID", "revisionId": "REV_ID"}'
```

## Notes

- Always include `includeItemsFromAllDrives`, `supportsAllDrives`, `corpora` for Shared Drive files
- Google Docs exported as text lose formatting
- For Sheets, specify a range to avoid downloading huge datasets
- The `fields` parameter reduces response size
- Full-text search only works on files owned or shared with you
