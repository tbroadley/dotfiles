# Agent Instructions

## Updating shell functions (devc, etc.)

When modifying shell functions like `devc` that exist in both:
- `/Users/thomas/dotfiles/.zshrc` (reference copy, committed to git)
- `/Users/thomas/.zshrc` (actual shell config on host)

**You must update BOTH files.** The dotfiles `.zshrc` is just a reference - the user's actual shell sources `~/.zshrc` directly, not the dotfiles version.
