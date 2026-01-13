# Agent Instructions

## Updating shell functions (devc, etc.)

When modifying shell functions like `devc` that exist in both:
- `/Users/thomas/dotfiles/.zshrc` (reference copy, committed to git)
- `/Users/thomas/.zshrc` (actual shell config on host)

**You must update BOTH files.** The dotfiles `.zshrc` is just a reference - the user's actual shell sources `~/.zshrc` directly, not the dotfiles version.

## NEVER overwrite ~/.zshrc

**CRITICAL:** The user's `~/.zshrc` contains personal configuration that is NOT in the dotfiles version. NEVER copy or overwrite `~/.zshrc` with the dotfiles version.

When asked to "update" or "sync" the local zshrc:
- Use the Edit tool to add/modify only the specific functions or lines that changed
- NEVER use `cp` to replace the entire file
- The dotfiles `.zshrc` only contains dev container functions - the user's actual `~/.zshrc` has many other things (PATH exports, aliases, tool configs, prompt settings, etc.)
