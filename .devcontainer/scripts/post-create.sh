#!/bin/bash
# Runs INSIDE the container after creation (devcontainer postCreateCommand).
# 1. Ensures api.env exists (local defaults, no external secrets needed)
# 2. Installs yarn dependencies for all packages
# 3. Installs pre-commit and sets up git hooks

set -e

DEVCONTAINER_DIR="/krakenkey/.devcontainer"
ENV_DIR="$DEVCONTAINER_DIR/env"

# ─── 1. Ensure api.env exists ───────────────────────────────────────────────

if [ ! -f "$ENV_DIR/api.env" ]; then
	echo "Creating api.env from local defaults..."
	cp "$ENV_DIR/api.env.local-defaults" "$ENV_DIR/api.env"
fi

# ─── 2. VS Code workspace symlink ─────────────────────────────────────────────
# VS Code expects the workspace at /workspaces/<name> but this container
# mounts the repo at /krakenkey. Create a symlink so VS Code can find it.
if [ ! -e /workspaces/krakenkey ]; then
  sudo mkdir -p /workspaces
  sudo ln -s /krakenkey /workspaces/krakenkey
  sudo chown -h node:node /workspaces/krakenkey
fi

# ─── 3. Auth persistence (bind-mounted from host) ───────────────────────────
# ~/.claude and ~/.config/gh are bind-mounted from the host (see
# docker-compose.yml), so auth tokens survive container rebuilds.
if [ -d "${HOME}/.claude" ]; then
	echo "Claude Code data bind-mounted from host at ${HOME}/.claude"
fi
if [ -d "${HOME}/.config/gh" ]; then
	echo "GitHub CLI config bind-mounted from host at ${HOME}/.config/gh"
fi

# ─── 3. Install yarn dependencies ─────────────────────────────────────────────

echo ""
echo "Installing yarn dependencies..."

cd /krakenkey/app/shared && yarn install
cd /krakenkey/app/backend && yarn install
cd /krakenkey/app/frontend && yarn install
cd /krakenkey/web && npm install

# ─── 4. Pre-commit hooks ──────────────────────────────────────────────────────

echo ""
echo "Setting up pre-commit hooks..."

# Use a project venv in the user's home so we don't try to modify the system-managed Python (PEP 668)
PYVENV_DIR="${HOME}/.venv/krakenkey"
mkdir -p "${HOME}/.venv"
if [ ! -d "$PYVENV_DIR" ]; then
  python3 -m venv "$PYVENV_DIR"
  "$PYVENV_DIR/bin/pip" install --upgrade pip setuptools wheel >/dev/null
fi

# Install pre-commit into the venv and run the venv's pre-commit binary
"$PYVENV_DIR/bin/pip" install pre-commit --quiet
cd /krakenkey     && "$PYVENV_DIR/bin/pre-commit" install
cd /krakenkey/app && "$PYVENV_DIR/bin/pre-commit" install

# Ensure new terminals auto-activate the venv (idempotent)
BASH_RC="${HOME}/.bashrc"
PROFILE="${HOME}/.profile"
SNIP_MARKER="# krakenkey venv auto-activation"

if ! grep -q "$SNIP_MARKER" "$BASH_RC" 2>/dev/null; then
  cat >> "$BASH_RC" <<'BASH_SNIPPET'

# krakenkey venv auto-activation
if [[ $- == *i* ]] && [ -f "${HOME}/.venv/krakenkey/bin/activate" ] && [ -z "$VIRTUAL_ENV" ]; then
  # shellcheck source=/dev/null
  source "${HOME}/.venv/krakenkey/bin/activate"
fi
BASH_SNIPPET
fi

# Also add to ~/.profile so login shells pick it up (safe/ignored if already present)
if [ -f "$PROFILE" ] && ! grep -q "$SNIP_MARKER" "$PROFILE" 2>/dev/null; then
  cat >> "$PROFILE" <<'PROFILE_SNIPPET'

# krakenkey venv auto-activation
if [ -f "${HOME}/.venv/krakenkey/bin/activate" ] && [ -z "$VIRTUAL_ENV" ]; then
  # shellcheck source=/dev/null
  source "${HOME}/.venv/krakenkey/bin/activate"
fi
PROFILE_SNIPPET
fi

echo ""
echo "Post-create setup complete."
echo ""
echo "Start the dev servers:"
echo "  API:      cd /krakenkey/app/backend  && yarn start:dev"
echo "  Frontend: cd /krakenkey/app/frontend && yarn dev --host"
echo ""
echo "Pre-commit hooks are active — secrets detection and YAML/JSON"
echo "linting will run automatically on each commit."
