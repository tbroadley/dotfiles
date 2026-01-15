# Claude Code Instructions

## About This Repo

Personal dotfiles for dev container setup. The `install.sh` script configures a consistent development environment inside containers.

### What Gets Installed

**CLI Tools** (Linux, user-local to `~/.local/bin`):
- ripgrep (`rg`) - fast search
- jq - JSON processor
- gh - GitHub CLI
- zoxide - smart `cd` replacement (`z` command)
- nvm + Node.js LTS
- Claude Code CLI
- @openai/codex

**Shell Configuration**:
- inputrc: arrow-key history search
- gitconfig/gitignore: git aliases and global ignores
- Shell aliases: `g`=git, `d`=dvc, `pt`=pytest, `cl`=claude, etc.
- Environment: `ANTHROPIC_MODEL=opus`, `EDITOR=vim`

**Claude Code Setup** (copied from `claude/`):
- `settings.json`: permissions, hooks, model preferences
- `CLAUDE.md`: global coding style rules
- `hooks/`: pre-tool-use scripts
- `skills/`: custom skill definitions

**Host Integration** (for dev containers):
- `open-url-on-host`: forward URLs to host browser
- `cursor-in-container`: open files in Cursor on host
- `pbcopy`/`pbpaste`: clipboard forwarding
- `improve`: Todoist watcher for autonomous tasks

### Key Files

| File | Purpose |
|------|---------|
| `install.sh` | Main setup script, runs in containers |
| `devc.zsh` | Host-side function to launch containers with auth forwarding |
| `claude/CLAUDE.md` | Global coding style rules (symlinked to `~/.claude/CLAUDE.md`) |
| `claude/settings.json` | Claude Code permissions and hooks |
| `bin/improve` | Todoist polling script for autonomous Claude Code tasks |

## Global CLAUDE.md

`~/.claude/CLAUDE.md` is a symlink to `claude/CLAUDE.md` in this repo. Edit the file here directly.

## Testing install.sh

Before pushing any changes to this repository, test that `install.sh` works by running it in a copy of an existing dev container:

```bash
# 1. Find a running dev container
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Image}}"

# 2. Create a test container from the dev container image (replace IMAGE_NAME)
docker run --rm -d --name dotfiles-test-container \
  --entrypoint /bin/bash \
  -v "$PWD:/dotfiles:ro" \
  IMAGE_NAME \
  -c "sleep infinity"

# 3. Run the install script
docker exec dotfiles-test-container bash -c "cd /dotfiles && ./install.sh"

# 4. Verify installations worked
docker exec dotfiles-test-container bash -c "
  export PATH=\"\$HOME/.local/bin:\$PATH\"
  source ~/.nvm/nvm.sh
  echo 'ripgrep:' && rg --version | head -1
  echo 'node:' && node --version
  echo 'claude:' && claude --version
"

# 5. Clean up
docker stop dotfiles-test-container
```

The script should complete without errors and all tools should be accessible.
