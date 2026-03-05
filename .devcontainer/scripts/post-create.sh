#!/bin/bash
# Runs INSIDE the container after creation (devcontainer postCreateCommand).
# 1. Ensures api.env exists (local defaults, no external secrets needed)
# 2. Installs yarn dependencies for all packages
# 3. Installs pre-commit and sets up git hooks

set -e

DEVCONTAINER_DIR="/workspaces/.devcontainer"
ENV_DIR="$DEVCONTAINER_DIR/env"

# ─── 1. Ensure api.env exists ───────────────────────────────────────────────

if [ ! -f "$ENV_DIR/api.env" ]; then
	echo "Creating api.env from local defaults..."
	cp "$ENV_DIR/api.env.local-defaults" "$ENV_DIR/api.env"
fi

# ─── 2. Install yarn dependencies ─────────────────────────────────────────────

echo ""
echo "Installing yarn dependencies..."

cd /workspaces/app/shared && yarn install
cd /workspaces/app/backend && yarn install
cd /workspaces/app/frontend && yarn install

# ─── 3. Pre-commit hooks ──────────────────────────────────────────────────────

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
cd /workspaces     && "$PYVENV_DIR/bin/pre-commit" install
cd /workspaces/app && "$PYVENV_DIR/bin/pre-commit" install

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
echo "  API:      cd /workspaces/app/backend  && yarn start:dev"
echo "  Frontend: cd /workspaces/app/frontend && yarn dev --host"
echo ""
echo "Pre-commit hooks are active — secrets detection and YAML/JSON"
echo "linting will run automatically on each commit."
