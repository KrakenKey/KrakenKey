# Contributing to KrakenKey

Thanks for your interest in contributing to KrakenKey. Whether it's a bug report, feature suggestion, documentation improvement, or code contribution -- we appreciate it.

## How to Contribute

- **Found a bug?** Open a [Bug Report](https://github.com/krakenkey/krakenkey/issues/new?template=bug_report.yml)
- **Have an idea?** Open a [Feature Request](https://github.com/krakenkey/krakenkey/issues/new?template=feature_request.yml)
- **Have a question?** Start a thread in [GitHub Discussions](https://github.com/krakenkey/krakenkey/discussions)
- **Found a security issue?** See [SECURITY.md](SECURITY.md) -- do NOT open a public issue
- **Want to submit code?** See the pull request process below

## Development Setup

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Docker | 20+ | Container runtime for devcontainer |
| VS Code | Latest | IDE with Dev Containers extension |
| Dev Containers extension | Latest | One-click dev environment |

### Getting Started

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/krakenkey/krakenkey.git
cd krakenkey

# Open in VS Code
code .
```

When prompted, click **Reopen in Container**. The devcontainer starts PostgreSQL, Redis, Traefik, and installs all dependencies automatically.

### Submodules vs. nested repositories

Not every directory in the checkout is a submodule, and the distinction matters when you commit:

- **Submodules** (`app/`, `web/`, `cli/`, `probe/`, `actions/cert-action/`, `examples/`) are registered in `.gitmodules`. `--recurse-submodules` clones them, and changes land as a gitlink pointer bump in this repo plus a commit in the submodule's own repo.
- **Nested repositories** (`infra/`, `internal/`) are independent git repositories that happen to sit inside the checkout. They are listed in `.gitignore`, are **not** in `.gitmodules`, and are not cloned by `--recurse-submodules` — you clone them separately. This repo tracks nothing about them, so commits there are invisible to superrepo tooling.
- A few KrakenKey repositories are not in the checkout at all and are cloned standalone: [`infra-int`](https://github.com/krakenkey/infra-int) (internal infrastructure docs and Terraform) and [`terraform-provider-krakenkey`](https://github.com/krakenkey/terraform-provider-krakenkey).

If a tool reports `infra/` or `internal/` as untracked, or a superrepo `git status` looks clean after you edited files there, this is why.

Once inside the container:

```bash
# Start the backend
cd app/backend
yarn start:dev

# Start the frontend (separate terminal)
cd app/frontend
yarn dev
```

For full setup details including hosts file configuration and TLS setup, see [LOCAL_DEV.md](LOCAL_DEV.md).

### Pre-commit Hooks

Pre-commit hooks are installed automatically when the devcontainer starts. They run on every commit:

- **gitleaks** -- secrets detection (prevents accidental credential commits)
- **YAML/JSON validation** -- catches syntax errors in config files
- **Trailing whitespace** and **end-of-file** fixes

To run manually:

```bash
pre-commit run --all-files
```

## Pull Request Process

1. **Fork** the repository and create a branch from `main`
2. **Make your changes** -- follow existing code patterns and style
3. **Write tests** where applicable (see Running Tests below)
4. **Fill out the PR template** when submitting
5. PRs require one approval before merging

### Code Style

The project uses Prettier and ESLint, both configured in `app/backend/` and `app/frontend/`. Your editor should pick up the config automatically.

## Running Tests

### Backend

```bash
cd app/backend

yarn test          # Unit tests
yarn test:cov      # Unit tests with coverage report
yarn test:e2e      # End-to-end tests
```

### Frontend

```bash
cd app/frontend

yarn test          # Unit tests
yarn test:coverage # Tests with coverage
```

## Project Structure

```
krakenkey/
├── .devcontainer/       # Dev environment (Docker Compose, Traefik, TLS)
├── .github/             # Issue templates, PR template
├── app/                 # Application code (git submodule)
│   ├── backend/         # NestJS API
│   ├── frontend/        # React dashboard
│   ├── docs/            # User-facing docs (error handling, domain verification)
│   └── shared/          # Shared code
├── web/                 # Marketing site (Astro)
├── cli/                 # CLI tool (Go, git submodule)
├── probe/               # TLS monitoring probe (Go, git submodule)
├── actions/cert-action/ # Certificate GitHub Action (git submodule)
├── examples/            # Usage examples (git submodule)
├── infra/               # Infrastructure — separate repo, NOT a submodule (gitignored)
├── internal/            # Private working docs — separate repo, NOT a submodule (gitignored)
├── CONTRIBUTING.md      # This file
├── KNOWN_LIMITATIONS.md # Tracked limitations and constraints
├── LICENSE              # AGPL-3.0
├── LOCAL_DEV.md         # Full local development guide
├── README.md            # Project overview
└── SECURITY.md          # Security policy
```

## Known Limitation: OAuth Login

KrakenKey authenticates via Authentik (OIDC). The OAuth client secret is not included in the repository.

**What this means for contributors:**

- You cannot use SSO login without a valid client secret
- All other local development features (database, Redis, API, frontend) work without it

**Workarounds:**

- Request a development client secret from a project maintainer (for trusted contributors)
- Set up your own Authentik instance and configure a new OAuth2 provider

A dev auth bypass mode is planned to allow contributors to authenticate locally without an external identity provider.

## License

By contributing to KrakenKey, you agree that your contributions will be licensed under the [GNU Affero General Public License v3.0](LICENSE).
