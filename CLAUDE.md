# Claude Code Instructions

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
