---
name: hf-cli
description: Work with HuggingFace repos using the huggingface-cli. Use when the user wants to upload datasets, check PR diffs, manage repos, or interact with HuggingFace Hub.
---

# HuggingFace CLI

Use the `huggingface-cli` (aliased as `hf`) for all HuggingFace operations. Do NOT use web fetching or raw API calls.

## Authentication

The CLI uses the token from `~/.huggingface/token` or the `HF_TOKEN` environment variable.

## Common Commands

### Repo Info
```bash
hf repo info <REPO_ID>                    # e.g., hf repo info datasets/org/my-dataset
```

### Upload Files
```bash
hf upload <REPO_ID> <LOCAL_PATH> <REMOTE_PATH> --repo-type dataset
hf upload <REPO_ID> <LOCAL_DIR> . --repo-type dataset   # Upload entire directory
```

### Download Files
```bash
hf download <REPO_ID> --repo-type dataset --local-dir ./data
hf download <REPO_ID> <FILENAME> --repo-type dataset    # Single file
```

### Create a Repo
```bash
hf repo create <REPO_NAME> --type dataset --organization <ORG>
```

### List Files in a Repo
```bash
hf ls <REPO_ID> --repo-type dataset
```

## Working with PRs / Revisions

```bash
# Upload to a specific branch/revision
hf upload <REPO_ID> <LOCAL_PATH> <REMOTE_PATH> --repo-type dataset --revision <BRANCH>

# Create a PR by uploading to a new branch
hf upload <REPO_ID> <LOCAL_PATH> <REMOTE_PATH> --repo-type dataset --revision refs/pr/<PR_NUM>
```

## Tips

- Always specify `--repo-type dataset` for dataset repos (default is model)
- After uploading, verify file sizes and content match expectations
- For large uploads, the CLI handles chunked uploads automatically
- Use `hf whoami` to verify authentication
