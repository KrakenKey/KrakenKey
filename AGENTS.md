# AGENTS.md

Instructions and context for AI agents working on the KrakenKey project.

## What is KrakenKey?

KrakenKey is a TLS certificate management and endpoint monitoring platform. It automates certificate issuance via Let's Encrypt using ACME DNS-01 challenges, and monitors TLS health on user-defined endpoints via a Go probe binary.

Users add a domain, set up two DNS records (TXT for ownership, CNAME to delegate ACME challenges), then submit CSRs to get certificates issued in ~4 minutes. Private keys never leave the user's device.

The probe component scans endpoints for TLS certificate status, expiry, chain validity, and connection health. It runs in three modes: standalone (local-only), connected (reports to KrakenKey API), and hosted (KrakenKey-operated infrastructure).

## Repository Layout

This is a monorepo with git submodules:

```
/krakenkey/
  app/              # Core application (submodule)
    backend/        # NestJS 11 REST API (TypeScript)
    frontend/       # React 19 + Vite 7 + Tailwind 4 (TypeScript)
    shared/         # Shared types and API route constants (@krakenkey/shared)
  cli/              # CLI tool (Go 1.26)
  web/              # Marketing site (Astro 5, static, Cloudflare Pages)
  infra/            # Infrastructure (Terraform, Docker Compose, scripts)
  probe/            # TLS endpoint monitoring probe (Go 1.23)
  actions/          # Custom GitHub Actions
    cert-action/    # Certificate management GitHub Action
  tools/            # AI agent skill definitions
    krakenkey-api/  # API tool definitions and workflows
    krakenkey-cli/  # CLI tool definitions and workflows
  .devcontainer/    # Local dev environment (Traefik + TLS + Postgres + Redis)
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | NestJS 11, TypeORM, BullMQ (Redis), acme-client |
| Frontend | React 19, Vite 7, Tailwind 4, Axios |
| Database | PostgreSQL 18 |
| Cache/Queue | Redis 8.6 |
| Auth | Authentik (OIDC) + API keys (`kk_` prefix) + Service keys (`kk_svc_` prefix) |
| API Docs | Swagger/OpenAPI (available at `/swagger-json`) |
| Marketing | Astro 5, custom CSS |
| CLI | Go 1.26, manual flag-based routing |
| Probe | Go 1.23, TLS scanning, JSON state file |
| Infra | Terraform (AWS + Cloudflare), Docker Compose |
| CI/CD | GitHub Actions, GHCR container images |

## Development

### Package Manager

Always use `yarn`, not npm.

### Running Locally

The devcontainer provides a full environment with TLS via Traefik:

```bash
# Terminal 1 -- API
cd app/backend && yarn start:dev

# Terminal 2 -- Frontend
cd app/frontend && yarn dev --host
```

Access at `https://dev.krakenkey.io` (requires hosts file entry: `127.0.0.1 dev.krakenkey.io api-dev.krakenkey.io`).

### Testing

```bash
# Backend (Jest 30)
cd app/backend && yarn test

# Frontend (Vitest 4)
cd app/frontend && yarn test --run

# CLI (Go test)
cd cli && go test ./...

# Probe (Go test)
cd probe && go test ./... -race
```

Always run tests after making changes. Tests must pass before work is considered complete.

### Type Checking

```bash
# Catches stricter Docker build errors (isolatedModules + emitDecoratorMetadata)
cd app/backend && npx tsc --noEmit
```

### Shared Library Changes

After modifying `app/shared/`, rebuild and reinstall:

```bash
cd app/shared && yarn build
rm -rf app/backend/node_modules/@krakenkey/shared && yarn install --check-files
```

The `@krakenkey/shared` package uses `file:` dependencies (copied, not symlinked).

### Pre-commit Hooks

gitleaks, hadolint, terraform fmt/validate, markdown lint, ESLint. Do not skip hooks (`--no-verify`).

### Lint and Type Errors

Resolve all TypeScript errors and ESLint warnings before considering work complete.

## API Overview

Base URL: `https://api.krakenkey.io` (production), `https://api-dev.krakenkey.io` (dev)

OpenAPI spec: `GET /swagger-json` (always available). Swagger UI: `GET /swagger` (dev only).

### Authentication

Three methods, all via `Authorization: Bearer <token>`:

1. **JWT** -- obtained through Authentik OAuth flow (`/auth/login` -> callback -> JWT)
2. **User API Key** -- persistent keys prefixed `kk_`, created via `POST /auth/api-keys`. Used by CLI and connected probes.
3. **Service Key** -- internal keys prefixed `kk_svc_`, for hosted probe infrastructure. Seeded from `KK_PROBE_API_KEY` env var.

The probe endpoints (`/probes/*`) accept either user API keys or service keys (dual auth). All other authenticated endpoints accept JWT or user API keys.

### Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/` | No | API status and version |
| GET | `/health` | No | Liveness check |
| GET | `/health/readiness` | No | Readiness (DB, Redis, Authentik) |
| POST | `/public/scan` | No | Scan a public TLS endpoint (unauthenticated, SSRF-protected, per-IP rate-limited) |
| GET | `/auth/login` | No | Redirect to Authentik login |
| GET | `/auth/register` | No | Redirect to Authentik registration |
| GET | `/auth/callback` | No | OAuth callback (returns tokens) |
| GET | `/auth/profile` | Yes | Current user profile with resource counts |
| PATCH | `/auth/profile` | Yes | Update profile / notification prefs |
| GET | `/auth/api-keys` | Yes | List API keys |
| POST | `/auth/api-keys` | Yes | Create API key (returns `kk_...` once) |
| DELETE | `/auth/api-keys/:id` | Yes | Delete API key |
| POST | `/auth/confirm-auto-renewal` | Yes | Confirm auto-renewal intent |
| GET | `/domains` | Yes | List domains |
| POST | `/domains` | Yes | Register domain |
| GET | `/domains/:id` | Yes | Get domain details |
| POST | `/domains/:id/verify` | Yes | Trigger DNS verification |
| DELETE | `/domains/:id` | Yes | Delete domain |
| GET | `/endpoints` | Yes | List monitored endpoints |
| POST | `/endpoints` | Yes | Create monitored endpoint (plan limit enforced) |
| GET | `/endpoints/:id` | Yes | Get endpoint details |
| PATCH | `/endpoints/:id` | Yes | Update endpoint (sni, label, isActive) |
| DELETE | `/endpoints/:id` | Yes | Delete endpoint |
| POST | `/endpoints/:id/regions` | Yes | Add hosted probe region (Starter tier+) |
| DELETE | `/endpoints/:id/regions/:region` | Yes | Remove hosted probe region |
| GET | `/endpoints/:id/results` | Yes | Paginated scan results |
| GET | `/endpoints/:id/results/latest` | Yes | Latest scan result per probe |
| POST | `/probes/register` | Dual | Register or heartbeat a probe |
| POST | `/probes/report` | Dual | Submit scan results |
| GET | `/probes/:id/config` | Dual | Fetch endpoint list for probe |
| GET | `/certs/tls` | Yes | List certificates |
| POST | `/certs/tls` | Yes | Submit CSR for issuance |
| GET | `/certs/tls/:id` | Yes | Get certificate details |
| GET | `/certs/tls/:id/details` | Yes | Get parsed cert details (issued only) |
| GET | `/certs/tls/:id/chain` | Yes | Get leaf and intermediate chain details; returns `chainPem` (intermediates) and `fullChainPem` (leaf + intermediates) |
| PATCH | `/certs/tls/:id` | Yes | Update cert (e.g., autoRenew toggle) |
| POST | `/certs/tls/:id/renew` | Yes | Renew certificate |
| POST | `/certs/tls/:id/retry` | Yes | Retry failed issuance |
| POST | `/certs/tls/:id/revoke` | Yes | Revoke certificate |
| DELETE | `/certs/tls/:id` | Yes | Delete failed/revoked cert |
| GET | `/users` | Yes | List users (admin only) |
| GET | `/users/:id` | Yes | Get user |
| PATCH | `/users/:id` | Yes | Update user |
| DELETE | `/users/:id` | Yes | Delete user (cascades) |
| POST | `/organizations` | Yes | Create organization |
| GET | `/organizations/:id` | Yes | Get org with members |
| PATCH | `/organizations/:id` | Yes | Update org |
| DELETE | `/organizations/:id` | Yes | Delete org (owner only) |
| POST | `/organizations/:id/members` | Yes | Invite member |
| PATCH | `/organizations/:id/members/:userId` | Yes | Update member role |
| DELETE | `/organizations/:id/members/:userId` | Yes | Remove member |
| POST | `/organizations/:id/transfer-ownership` | Yes | Transfer org ownership |
| POST | `/billing/checkout` | Yes | Create Stripe checkout session |
| GET | `/billing/subscription` | Yes | Get subscription status |
| POST | `/billing/portal` | Yes | Create Stripe portal session |
| POST | `/billing/upgrade/preview` | Yes | Preview upgrade cost |
| POST | `/billing/upgrade` | Yes | Upgrade subscription |
| POST | `/feedback` | Yes | Submit feedback |

"Dual" auth means the endpoint accepts either a user API key (`kk_`) or a service key (`kk_svc_`).

### Error Format

All errors follow this structure:

```json
{
  "statusCode": 400,
  "message": "Invalid CSR PEM format",
  "error": "Bad Request",
  "timestamp": "2026-03-24T10:30:00.000Z",
  "path": "/certs/tls"
}
```

Validation errors return `message` as an array of strings. Plan limit errors include `code: "plan_limit_exceeded"`, `limit`, `current`, and `plan` fields.

### Rate Limiting

Tier-aware, tracked by user ID (authenticated) or IP (unauthenticated):

| Tier | Public | Reads | Writes | Expensive |
|------|--------|-------|--------|----------|
| free | 30/min | 60/min | 20/min | 5/hr |
| starter | 60/min | 120/min | 40/min | 10/hr |
| team | 60/min | 300/min | 60/min | 30/hr |
| business | 120/min | 600/min | 120/min | 60/hr |
| enterprise | 120/min | 1000/min | 200/min | 100/hr |

Expensive operations: cert issuance, renewal, retry, revocation, domain verification.

### Plan Limits

| Resource | Free | Starter | Team | Business | Enterprise |
|----------|------|---------|------|----------|------------|
| Domains | 3 | 10 | 25 | 75 | unlimited |
| API keys | 2 | 5 | 10 | 25 | unlimited |
| Certs/month | 5 | 50 | 250 | 1000 | unlimited |
| Total active certs | 10 | 75 | 375 | 1500 | unlimited |
| Concurrent pending | 2 | 5 | 25 | 100 | unlimited |
| Renewal window | 5d | 30d | 30d | 30d | 30d |
| Monitored endpoints | 3 | 10 | 50 | 200 | unlimited |
| Min scan interval | 60m | 30m | 5m | 1m | 1m |
| Hosted probe regions | - | 2 | 5 | 15 | unlimited |
| Hosted endpoints | - | 5 | 25 | 100 | unlimited |
| Hosted scan interval | - | 30m | 15m | 5m | 1m |
| Scan result retention | 5d | 30d | 90d | 90d | 90d |

Free tier gets connected probes only. Hosted monitoring starts at Starter tier.

### Certificate Lifecycle

```
pending -> issuing -> issued -> renewing -> issued (renewed)
                  \-> failed  (retry possible)
issued -> revoking -> revoked (delete possible)
```

Issuance is asynchronous via BullMQ. Typical time: 2-5 minutes. Poll `GET /certs/tls/:id` for status.

### Probe Modes

| Mode | Auth | Endpoint Source | Results Storage | Use Case |
|------|------|----------------|-----------------|----------|
| standalone | None | Local YAML config | Local JSON state | OSS self-monitoring |
| connected | User API key (`kk_`) | API or local config | API | Customer self-hosted probe |
| hosted | Service key (`kk_svc_`) | API (by region) | API | KrakenKey-operated infrastructure |

## CLI Overview

The `krakenkey` CLI (`cli/` directory) provides terminal access to all KrakenKey API features.

### Installation

```bash
# From source
cd cli && go build -o krakenkey ./cmd/krakenkey

# Pre-built binaries available via GitHub Releases (goreleaser)
```

### Authentication

```bash
krakenkey auth login --api-key kk_...    # Save API key to config
krakenkey auth status                     # Show current user
krakenkey auth logout                     # Remove stored key
```

Config stored at `~/.config/krakenkey/config.yaml`. API key can also be set via `KK_API_KEY` env var.

### Commands

| Command | Subcommands | Description |
|---------|-------------|-------------|
| `auth` | login, logout, status, keys (list/create/delete) | Authentication and API key management |
| `domain` | add, list, show, verify, delete | Domain registration and verification |
| `cert` | issue, submit, list, show, download, renew, revoke, retry, update, delete | Certificate lifecycle |
| `endpoint` | add, list, show, enable, disable, delete, scan, region (add/remove), probe (add/remove) | Endpoint monitoring |
| `account` | show, plan | Account and subscription info |

### Output Formats

```bash
krakenkey --output json domain list   # Machine-readable JSON
krakenkey domain list                  # Human-readable table (default)
krakenkey --no-color domain list       # Plain text without ANSI colors
```

### Global Flags

| Flag | Env Var | Description |
|------|---------|-------------|
| `--api-url` | `KK_API_URL` | API base URL |
| `--api-key` | `KK_API_KEY` | API key |
| `--output` | `KK_OUTPUT` | Output format: text or json |
| `--no-color` | - | Disable colored output |
| `--verbose` | - | Enable verbose logging |

## Key Patterns

- **Environment variables**: all prefixed `KK_` (e.g., `KK_DB_HOST`, `KK_API_PORT`)
- **Global guards**: JwtOrApiKeyGuard, TierAwareThrottlerGuard, RoleGuard, ServiceOrUserKeyGuard
- **Global pipe**: ValidationPipe (whitelist: true, transform: true -- strips unknown properties)
- **Global filter**: HttpExceptionFilter (standard error format above)
- **Migrations**: auto-run on startup (`migrationsRun: true`, `synchronize: false`)
- **ACME DNS strategy**: CloudflareDnsStrategy / Route53DnsStrategy (strategy pattern)
- **Frontend state**: React Context (AuthContext, DomainsContext) with Axios interceptors
- **CSR generation**: client-side only (Web Crypto API in browser, Go crypto stdlib in CLI)
- **Endpoint monitoring**: Go probe binary scans TLS endpoints; NestJS API receives and stores results
- **Dual auth**: Probe endpoints accept user API keys or service keys via ServiceOrUserKeyGuard
- **Cron jobs**: probe staleness detection (3 AM), scan result retention cleanup (4 AM), domain re-verification (2 AM), cert expiry monitoring (6 AM)

## Writing Style

When generating user-facing content: avoid em dashes, "delve", "leverage", "elevate", "streamline", "robust", "seamless", and other patterns commonly associated with AI-generated text. Write naturally and directly.

## AI Agent Skills

See [tools/](tools/) for structured skill definitions that AI agents can use:

- **[krakenkey-api](tools/krakenkey-api/)** -- Tool definitions and workflows for the KrakenKey REST API. Covers all endpoints including endpoint monitoring, probe management, certificate lifecycle, domain verification, billing, and organizations.
- **[krakenkey-cli](tools/krakenkey-cli/)** -- Tool definitions and workflows for the `krakenkey` CLI. Covers all commands: auth, domain, cert, endpoint, and account.
