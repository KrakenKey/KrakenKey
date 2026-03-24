# AGENTS.md

Instructions and context for AI agents working on the KrakenKey project.

## What is KrakenKey?

KrakenKey is a TLS certificate management platform that automates issuance via Let's Encrypt using ACME DNS-01 challenges. Users add a domain, set up two DNS records (TXT for ownership, CNAME to delegate ACME challenges), then submit CSRs to get certificates issued in ~4 minutes.

Private keys never leave the user's device. CSRs are generated client-side (browser WebCrypto API or OpenSSL). KrakenKey only handles the ACME flow on its infrastructure.

## Repository Layout

This is a monorepo with git submodules:

```
/workspaces/
  app/              # Core application (submodule)
    backend/        # NestJS 11 REST API (TypeScript)
    frontend/       # React 19 + Vite 7 + Tailwind 4 (TypeScript)
    shared/         # Shared types and API route constants (@krakenkey/shared)
  cli/              # CLI tool (Go 1.26, skeleton -- not yet implemented)
  web/              # Marketing site (Astro 5, static, Cloudflare Pages)
  infra/            # Infrastructure (Terraform, Docker Compose, scripts)
  probe/            # Health probe tool
  .devcontainer/    # Local dev environment (Traefik + TLS + Postgres + Redis)
```

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | NestJS 11, TypeORM, BullMQ (Redis), acme-client |
| Frontend | React 19, Vite 7, Tailwind 4, Axios |
| Database | PostgreSQL 18 |
| Cache/Queue | Redis 8.6 |
| Auth | Authentik (OIDC) + API keys (`kk_` prefix) |
| API Docs | Swagger/OpenAPI (available at `/swagger-json`) |
| Marketing | Astro 5, custom CSS |
| CLI | Go 1.26, cobra-style manual routing |
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

gitleaks, hadolint, terraform fmt/validate, markdown lint. Do not skip hooks (`--no-verify`).

### Lint and Type Errors

Resolve all TypeScript errors and ESLint warnings before considering work complete.

## API Overview

Base URL: `https://api.krakenkey.io` (production), `https://api-dev.krakenkey.io` (dev)

OpenAPI spec: `GET /swagger-json` (always available). Swagger UI: `GET /swagger` (dev only).

### Authentication

Two methods, both via `Authorization: Bearer <token>`:

1. **JWT** -- obtained through Authentik OAuth flow (`/auth/login` -> callback -> JWT)
2. **API Key** -- persistent keys prefixed `kk_`, created via `POST /auth/api-keys`

API keys are SHA-256 hashed in the database. The plaintext key is returned only once at creation.

### Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/` | No | API status and version |
| GET | `/health` | No | Liveness check |
| GET | `/health/readiness` | No | Readiness (DB, Redis, Authentik) |
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
| GET | `/certs/tls` | Yes | List certificates |
| POST | `/certs/tls` | Yes | Submit CSR for issuance |
| GET | `/certs/tls/:id` | Yes | Get certificate details |
| GET | `/certs/tls/:id/details` | Yes | Get parsed cert details (issued only) |
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

Validation errors return `message` as an array of strings.

### Rate Limiting

Tier-aware, tracked by user ID (authenticated) or IP (unauthenticated):

| Tier | Public | Reads | Writes | Expensive |
|------|--------|-------|--------|-----------|
| free | 30/min | 60/min | 20/min | 5/hr |
| starter | 60/min | 120/min | 40/min | 10/hr |
| team | 60/min | 300/min | 60/min | 30/hr |
| business | 120/min | 600/min | 120/min | 60/hr |
| enterprise | 120/min | 1000/min | 200/min | 100/hr |

Expensive operations: cert issuance, renewal, retry, revocation, domain verification.

### Certificate Lifecycle

```
pending -> issuing -> issued -> renewing -> issued (renewed)
                  \-> failed  (retry possible)
issued -> revoking -> revoked (delete possible)
```

Issuance is asynchronous via BullMQ. Typical time: 2-5 minutes. Poll `GET /certs/tls/:id` for status.

## Key Patterns

- **Environment variables**: all prefixed `KK_` (e.g., `KK_DB_HOST`, `KK_API_PORT`)
- **Global guards**: JwtOrApiKeyGuard, TierAwareThrottlerGuard, RoleGuard
- **Global pipe**: ValidationPipe (whitelist: true, transform: true -- strips unknown properties)
- **Global filter**: HttpExceptionFilter (standard error format above)
- **Migrations**: auto-run on startup (`migrationsRun: true`, `synchronize: false`)
- **ACME DNS strategy**: CloudflareDnsStrategy / Route53DnsStrategy (strategy pattern)
- **Frontend state**: React Context (AuthContext, DomainsContext) with Axios interceptors
- **CSR generation**: client-side only (Web Crypto API in browser, Go crypto stdlib in CLI)

## Writing Style

When generating user-facing content: avoid em dashes, "delve", "leverage", "elevate", "streamline", "robust", "seamless", and other patterns commonly associated with AI-generated text. Write naturally and directly.

## AI Agent API Tooling

See [tools/krakenkey-api/](tools/krakenkey-api/) for structured tool definitions that AI agents can use to interact with the KrakenKey API programmatically.
