---
name: design-doc
description: Create an engineering design document from conversation context using the Google Drive template.
user-invocable: true
---

# Design Document Generator

Create an engineering design document based on the current conversation context, following the team's standard template from Google Drive.

## Prerequisites

Requires `gws` CLI with auth configured. See `../gws-shared/SKILL.md`.

## When to Use

Use this skill when the user:
- Asks to create a design doc
- Wants to document a technical decision or architecture
- Needs to write up a feature proposal
- Says `/design-doc`

## Workflow

### 1. Find the Template in Google Drive

```bash
gws drive files list --params '{
  "q": "name contains '\''engineering design doc template'\'' and mimeType = '\''application/vnd.google-apps.document'\''",
  "fields": "files(id,name,mimeType,webViewLink)",
  "includeItemsFromAllDrives": true,
  "supportsAllDrives": true,
  "corpora": "allDrives"
}'
```

### 2. Read the Template

Export the template as plain text to understand its structure:

```bash
gws drive files export --params '{"fileId": "TEMPLATE_DOC_ID", "mimeType": "text/plain"}'
```

### 3. Analyze the Template

The template will contain:
- Section headings (e.g., Summary, Background, Goals, Non-Goals, Design, Alternatives, etc.)
- Instructions or placeholders for what to include in each section
- Formatting guidance

Extract the structure and understand what each section should contain.

### 4. Generate the Design Document

Using the conversation history as context, create a design document that:
- Follows the exact section structure from the template
- Fills in each section with relevant content from the conversation
- Uses appropriate technical detail for each section
- Maintains a professional, clear writing style

If the conversation doesn't contain enough information for certain sections:
- Mark them with `[TODO: <what's needed>]`
- Or ask the user for the missing information before generating

### 5. Determine the Filename

Ask the user what to name the file, or derive it from the document title/summary:
- Use kebab-case: `feature-name-design.md`
- Default location: current working directory

### 6. Write the Document

Write the generated design doc as a markdown file.

### 7. Report to User

After writing the file:
- Tell the user the file path
- Mention any `[TODO]` sections that need to be filled in
- Remind them how to paste into Google Docs with formatting:

**Pasting into Google Docs:**

1. Copy the Markdown content to your clipboard from the file
2. In your Google Docs document, right-click where you want to paste
3. From the context menu, select **"Paste from Markdown"**

## Notes

- The template structure may vary - always read the actual template first
- Keep the generated doc concise but complete
- If the conversation was exploratory, focus on the decisions that were made
- Include relevant code snippets or diagrams if discussed in the conversation
