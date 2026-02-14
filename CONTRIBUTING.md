# Contributing to KrakenKey

## Getting Started

1. Clone both repos under a common parent directory (see [Repo Layout](LOCAL_DEV.md#repo-layout))
2. Follow the [Local Development](LOCAL_DEV.md) guide to set up the devcontainer
3. Start the API and frontend as described in the guide

Pre-commit hooks are installed automatically when the devcontainer starts. They run secrets detection (gitleaks) and YAML/JSON validation on every commit. The devcontainer installs `pre-commit` into a per-user venv at `~/.venv/krakenkey` (created during `post-create`) and auto-activates it for new interactive terminals; you normally won't need to activate it manually. See [Pre-commit Hooks](LOCAL_DEV.md#pre-commit-hooks) for details.

## Known Limitations

### OAuth Login Requires a Client Secret

KrakenKey authenticates via Authentik (OIDC). The OAuth client secret (`AUTHENTIK_CLIENT_SECRET`) is not included in the repository and cannot be shared publicly.

**What this means for contributors:**

- You cannot use SSO login without a valid client secret
- All other local development features (DB, Redis, API, frontend) work without it

**Workarounds:**

- Request a development client secret from a project maintainer (for trusted contributors)
- Set up your own Authentik instance and configure a new OAuth2 provider

**Future:** A dev auth bypass mode is planned to allow contributors to authenticate locally without an external Authentik instance.
