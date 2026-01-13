# Agent Instructions

## Updating shell functions (devc, etc.)

When modifying shell functions like `devc` that exist in both:
- `/Users/thomas/dotfiles/.zshrc` (reference copy, committed to git)
- `/Users/thomas/.zshrc` (actual shell config on host)

**You must update BOTH files.** The dotfiles `.zshrc` is just a reference - the user's actual shell sources `~/.zshrc` directly, not the dotfiles version.

## Updating ~/.zshrc

The user's `~/.zshrc` contains personal configuration beyond what's in the dotfiles version (PATH exports, aliases, prompt settings, etc.). Don't overwrite it with `cp`.

When asked to "update" or "sync" the local zshrc, use the Edit tool to modify only the specific functions or lines that changed.
