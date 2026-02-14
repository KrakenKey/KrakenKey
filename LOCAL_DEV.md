# Local Development Environment

A VSCode devcontainer that runs the KrakenKey API and Web locally with full TLS, mirroring the remote dev environment. By pointing your hosts file at localhost, you get a seamless `https://dev.krakenkey.io` experience with hot reload.

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| Docker Desktop (or Docker Engine + Compose plugin) | Container runtime |
| VS Code + [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension | Opens the devcontainer |
| [`mkcert`](https://github.com/FiloSottile/mkcert#installation) installed on host | Generates locally-trusted TLS certificates |
| Both repos cloned under a common parent | `KrakenKey/infra/` and `KrakenKey/app/` side by side |

### Repo Layout

The devcontainer expects both repos cloned under a common parent directory:

```
KrakenKey/
├── .devcontainer/  ← devcontainer config lives here
├── infra/
├── app/
└── krakenkey.code-workspace  ← open this in VS Code
```

## Hosts File Configuration

Add to `/etc/hosts` (Linux/Mac) or `C:\Windows\System32\drivers\etc\hosts` (Windows):

```
127.0.0.1   dev.krakenkey.io api-dev.krakenkey.io
```

**Do NOT add `auth-dev.krakenkey.io`** — it must resolve to the remote Authentik server for OAuth to work.

## Starting the Environment

1. Open the `KrakenKey/` root folder (or the `krakenkey.code-workspace`) in VS Code
2. When prompted, click **"Reopen in Container"** (or `Ctrl+Shift+P` → "Dev Containers: Reopen in Container")
3. Wait for initialization (first time: generates TLS certs, creates env files, installs yarn deps, sets up pre-commit hooks)
4. Open two terminals in VS Code:

```bash
# Terminal 1 — API (NestJS with hot reload)
cd /workspaces/app/backend && yarn start:dev

# Terminal 2 — Frontend (Vite with HMR)
cd /workspaces/app/frontend && yarn dev --host
```

5. Browse to **https://dev.krakenkey.io**

## Architecture

```
Host browser
  │  hosts file: 127.0.0.1 dev.krakenkey.io api-dev.krakenkey.io
  │
  ├──► :443 Traefik (TLS termination)
  │       ├── Host(api-dev.krakenkey.io) ──► node:8080  (NestJS)
  │       └── Host(dev.krakenkey.io)     ──► node:5173  (Vite)
  │
  ├── postgres:5432  (local, postgres/postgres)
  └── redis:6379     (local, no password)

  Remote: auth-dev.krakenkey.io ──► EC2 Authentik (unchanged)
```

- **Traefik** handles TLS termination with locally-generated mkcert certificates
- **API and Web** run from source in the dev container with hot reload
- **Authentik** is the remote instance — no local SSO server needed
- **PostgreSQL** and **Redis** are local containers with simple credentials

## Switching Between Remote and Local

| Mode | Action |
|------|--------|
| **Local dev** | Add the hosts file entries above |
| **Remote dev** | Remove or comment out the hosts file entries |

That's it — the same URLs work in both cases.

## Environment Variables

Local development uses dummy defaults from `.devcontainer/env/api.env.local-defaults` — no external secrets are needed. Infrastructure values (DB, Redis hostnames, etc.) are in `.devcontainer/env/api-local-overrides.env`.

To customize environment variables, edit `.devcontainer/env/api.env` (gitignored).

**Note:** OAuth login requires a valid `AUTHENTIK_CLIENT_SECRET`. This secret is not included in the repository. If you are a team member, set the real client secret in `.devcontainer/env/api.env`. If you are an open-source contributor without access to the project's Authentik instance, see [CONTRIBUTING.md](./CONTRIBUTING.md#known-limitations) for details.

## Troubleshooting

### Certificate Warnings in Browser

Ensure `mkcert -install` was run on your host machine. This installs the local CA into your system trust store. If you still see warnings, try regenerating:

```bash
rm -f infra/docker/certs/local/*.pem
# Re-open the devcontainer — init.sh will regenerate them
```

### Port 443 Already in Use

Stop any local web servers, VPNs, or other containers using port 443 before opening the devcontainer.

### "Cannot Connect" After Starting Servers

- Verify hosts file entries: `cat /etc/hosts | grep krakenkey`
- Verify traefik is running: `docker ps | grep traefik`
- Check traefik dashboard at `http://localhost:8080`
- Ensure API is listening: the terminal should show `API listening on port 8080`
- Ensure Vite is listening: the terminal should show the local URL

### Auth Callback Fails

Ensure `auth-dev.krakenkey.io` is **NOT** in your hosts file. It must resolve to the remote Authentik server. The OAuth flow redirects to Authentik (remote) and back to `dev.krakenkey.io` (local).

### Existing app/.devcontainer Still Works

The root `KrakenKey/.devcontainer/` and `app/.devcontainer/` are completely independent. Opening `app/` in VS Code uses the simpler devcontainer (no Traefik, no TLS). Opening `KrakenKey/` uses this full-fidelity setup.

## Pre-commit Hooks

The devcontainer automatically installs [pre-commit](https://pre-commit.com) and activates the hooks defined in `.pre-commit-config.yaml`.

To avoid modifying the distribution-managed Python (PEP 668), `pre-commit` is installed into a per-user virtual environment at `~/.venv/krakenkey` during the devcontainer post-create step. The devcontainer also appends an idempotent snippet to your shell profile so new interactive terminals will auto-activate that venv — you should not need to `source` it manually.

If you need to run the bundled `pre-commit` directly, use:

```bash
~/.venv/krakenkey/bin/pre-commit --version
~/.venv/krakenkey/bin/pre-commit run --all-files
```

(If you prefer, `pipx` is another supported option for installing non-system Python CLIs.)

On every commit the following checks run:

| Hook | Purpose |
|------|---------|
| `check-yaml` | Validates YAML syntax (docker-compose, traefik configs) |
| `check-json` | Validates JSON syntax (devcontainer.json, package.json) |
| `check-merge-conflict` | Catches unresolved merge conflict markers |
| `trailing-whitespace` | Removes trailing whitespace |
| `end-of-file-fixer` | Ensures files end with a newline |
| `gitleaks` | Scans for secrets, tokens, and passwords |

To run all hooks manually against every file:

```bash
pre-commit run --all-files
```

To skip hooks for a one-off commit (not recommended):

```bash
git commit --no-verify
```
