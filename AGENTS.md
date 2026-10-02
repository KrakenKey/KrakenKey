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
  probe/            # TLS endpoint monitoring probe (Go 1.24)
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
| Probe | Go 1.24, TLS scanning, JSON state file |
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
| GET | `/endpoints/:id/results/export` | Yes | Export raw scan results (`?format=json` or `csv`) |
| POST | `/endpoints/:id/scan` | Yes | Request an on-demand scan |
| GET | `/endpoints/probes/mine` | Yes | List your connected probes available for assignment |
| POST | `/endpoints/:id/probes` | Yes | Assign connected probes to an endpoint |
| DELETE | `/endpoints/:id/probes/:probeId` | Yes | Unassign a connected probe |
| POST | `/probes/register` | Dual | Register or heartbeat a probe |
| POST | `/probes/report` | Dual | Submit scan results |
| GET | `/probes/:probeId/config` | Dual | Fetch endpoint list for probe |
| GET | `/certs/tls` | Yes | List certificates |
| POST | `/certs/tls` | Yes | Submit CSR for issuance |
| GET | `/certs/tls/:id` | Yes | Get certificate details |
| GET | `/certs/tls/:id/details` | Yes | Get parsed cert details (issued only) |
| GET | `/certs/tls/:id/chain` | Yes | Get intermediate chain details; `chainPem` and `fullChainPem` |
| PATCH | `/certs/tls/:id` | Yes | Update cert (e.g., autoRenew toggle) |
| POST | `/certs/tls/:id/renew` | Yes | Renew certificate |
| POST | `/certs/tls/:id/retry` | Yes | Retry failed issuance |
| POST | `/certs/tls/:id/revoke` | Yes | Revoke certificate |
| DELETE | `/certs/tls/:id` | Yes | Delete failed/revoked cert |
| POST | `/public-scan` | No | On-demand TLS scan; SSRF-protected, per-IP rate-limited |
| GET | `/users` | Yes | List users (admin only) |
| GET | `/users/:id` | Yes | Get user (own record or admin) |
| PATCH | `/users/:id` | Yes | Update user (own record or admin) |
| DELETE | `/users/:id` | Yes | Delete user, cascades (own record or admin) |
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

Validation errors return `message` as an array of strings. Branch on `statusCode`, not on `error`: some 4xx responses (plan limits, `429`) currently carry `"error": "Internal Server Error"`.

Plan limit errors return `402` (domains, API keys, certificates) or `403` (monitored endpoints, hosted regions and hosted endpoints), with a readable `message` such as `Monthly certificate limit reached`. The services attach `code: "plan_limit_exceeded"`, `limit`, `current` and `plan`, but the global exception filter currently drops them, so clients only see the standard fields above.

### Rate Limiting

Tier-aware and counted per route. JWT callers are tracked by user ID; API key and unauthenticated callers by client IP, so several API keys behind one NAT share a bucket. Details: [app/docs/RATE_LIMITING.md](https://github.com/KrakenKey/app/blob/main/docs/RATE_LIMITING.md).

| Tier | Public | Reads | Writes | Expensive |
|------|--------|-------|--------|-----------|
| free | 30/min | 60/min | 20/min | 5/hr |
| starter | 60/min | 120/min | 40/min | 10/hr |
| team | 60/min | 300/min | 60/min | 30/hr |
| business | 120/min | 600/min | 120/min | 60/hr |
| enterprise | 120/min | 1000/min | 200/min | 100/hr |

Expensive operations: cert issuance, renewal, retry, revocation, domain verification.

A `429` carries a `Retry-After` header (seconds); back off for at least that long. Allowed responses carry `X-RateLimit-Limit`, `X-RateLimit-Remaining` and `X-RateLimit-Reset`.

Separately, 10 failed API key attempts from one IP within 15 minutes lock that IP out of API key auth for 15 minutes (also `429`, message `Too many failed API key attempts`). An agent looping on a bad or revoked key will lock itself out; stop on the first `401` instead of retrying.

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

### Certificate Chain

An issued cert's PEM data comes from two places:

- `GET /certs/tls/:id` returns the cert record, including `crtPem` (leaf only) and `chainPem` (intermediates only).
- `GET /certs/tls/:id/chain` returns parsed chain info plus the concatenated full chain:

```json
{
  "leafCert": { "...": "parsed leaf details, same shape as /certs/tls/:id/details" },
  "intermediates": [
    { "serialNumber": "...", "issuer": "...", "subject": "...", "validFrom": "...", "validTo": "...", "fingerprint": "..." }
  ],
  "fullChainPem": "-----BEGIN CERTIFICATE-----..."
}
```

`fullChainPem` is leaf + intermediates. Most web servers (nginx, Caddy, HAProxy) expect the full chain. The CLI (`cert download --format cert|chain|fullchain`, `--chain-out`, `--fullchain-out`) and GitHub Action (`cert-path`, `chain-path`, `fullchain-path`) expose the same three forms.

### Issuance Notes for Agents

- **Retrying is safe.** Submitting the same CSR again within 15 minutes returns the original cert instead of creating a second one. If the first request is still being created, the retry gets `409 Conflict`; wait and poll.
- **CNAME delegation is checked before the ACME order.** If `_acme-challenge.<domain>` has no CNAME to KrakenKey's auth zone, or points elsewhere, the cert goes to `failed` on the first attempt with a message naming the exact record to create. Fix DNS, then `POST /certs/tls/:id/retry`. Do not loop on retry without changing DNS.
- **Failed issuances retry automatically** (3 attempts, ~5s and ~10s apart) unless the failure is permanent: invalid CSR, missing or wrong CNAME delegation, CA policy or CAA refusal, deactivated ACME account, or a CA rate limit.

### PKI Advisories

Developments in the public CA/browser ecosystem relevant to agents working on cert issuance or DNS automation:

- **SC-098v2 (CAA RFC 8657)** — CA enforcement of `accounturi`/`validationmethods` CAA parameters is mandatory from March 2027. If a user's CAA record sets `validationmethods`, it must include `dns-01` for KrakenKey issuance to keep working.
- **Chrome EKU separation** — enforced 2026-06-15; public serverAuth/clientAuth intermediates split. Let's Encrypt (KrakenKey's issuer) is unaffected.
- **CT mandatory logging** — enforced 2026-06-15; all publicly-trusted certs are CT-logged with no opt-out. Already true for Let's Encrypt certs KrakenKey issues.
- **Let's Encrypt Merkle Tree Certificates** — announced 2026-06-03 as LE's post-quantum issuance path; staging late 2026, production 2027. MTC does not use the `chain.pem`/`fullchain.pem` model above — `GetCertChain()`, the CLI chain flags, and the GitHub Action `chain-path`/`fullchain-path` outputs will need a compatibility pass before LE's production MTC rollout.
- **Mozilla Root Store Policy v3.1** — effective 2026-07-01; adds mass revocation planning (ballot SC-089), CP/CPS documentation, and a five-year root key age cap. No direct action needed for KrakenKey as a Let's Encrypt subscriber, but relevant context if evaluating additional CAs.
- **HARICA CP/CPS drift, two chained mass revocations** — July 2026: an `id-kp-clientAuth` EKU compliance lapse forced 66,105 cert revocations (July 20), followed by a missing OCSP AIA pointer incident forcing mass replacement by July 25. Not KrakenKey's issuer (Let's Encrypt), but the operational pattern is directly relevant here: OCSP stapling and mTLS break on affected certs, and ACME clients with ARI support (RFC 9773) absorb forced CA-initiated renewal far better than clients polling on a static schedule. Worth revisiting if KrakenKey ever adds ARI awareness to its own renewal polling. Tracked in web PR #42.
- **FreeRDP TLS certificate validation bypass (CVE-2026-66402)** — fixed in FreeRDP 3.29.0 (August 1, 2026): three flaws in FreeRDP's server-certificate matching (embedded-NUL SAN truncation, a CN fallback that ignores a non-matching SAN, and IP-literal targets checked against DNS SAN instead of `iPAddress` SAN) let a certificate that doesn't match the target host pass validation. Not a KrakenKey issuance defect — the bug is client-side matching logic, and correct issuance can't compensate for it — but relevant if any docs or examples ever point users at FreeRDP-based gateways (e.g., Guacamole, Remmina) using KrakenKey-issued certs. Tracked in web PR #44.
- **SC100 (DNSSEC validation consolidation)** — CA/Browser Forum ballot passed 2026-08-06; consolidates scattered DNSSEC validation language into BR Section 4.2.2.2 and clarifies that mandatory DNSSEC validation applies only to a CA's Primary Network Perspective, not the Remote Network Perspectives used for Multi-Perspective Issuance Corroboration. No behavior change for CAs — a reorganization and clarification of the existing SC-085v2 requirement (mandatory since March 2026). Relevant context if a user reports a DNS-01 renewal failure on a DNSSEC-signed zone: a `SERVFAIL` from the CA's primary perspective (e.g., during a DS/DNSKEY rollover) is a hard issuance block regardless of what other perspectives observe. Tracked in web PR #46.

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

# Pre-built binaries via GitHub Releases (goreleaser): krakenkey_<version>_<os>_<arch>.tar.gz
```

### Authentication

```bash
krakenkey auth login --api-key kk_...    # Save API key to config
krakenkey auth status                     # Show current user
krakenkey auth logout                     # Remove stored key
```

Config stored at `~/.config/krakenkey/config.yaml`. API key can also be set via `KK_API_KEY` env var. On non-Windows systems, the CLI refuses to load or save the config file if its permissions are broader than `0600` (fix: `chmod 600 ~/.config/krakenkey/config.yaml`).

### Commands

| Command | Subcommands | Description |
|---------|-------------|-------------|
| `auth` | login, logout, status, keys (list/create/delete) | Authentication and API key management |
| `domain` | add, list, show, verify, delete | Domain registration and verification |
| `cert` | issue, submit, list, show, download, renew, revoke, retry, update, delete | Certificate lifecycle |
| `endpoint` | add, list, show, enable, disable, delete, scan, probes, region (add/remove), probe (add/remove) | Endpoint monitoring |
| `account` | show, plan | Account and subscription info |
| `version` | - | Print version (`dev` for unversioned builds) |

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
| `--no-color` | `NO_COLOR` | Disable colored output |
| `--verbose` | - | Accepted but currently has no effect |
| `--version` | - | Print version and exit |

Global flags must come **before** the command (`krakenkey --output json domain list`). After the command they are ignored or rejected.

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Authentication error (401). A 403 exits 1 |
| 3 | Not found (404) |
| 4 | Rate limited (429) |
| 5 | Config error (no API key, bad config file permissions) |

Some errors are wrapped before they reach the exit handler (e.g. the submit step of `cert issue`), and those currently exit `1` instead of the specific code. Agents should read the error message too, not only the exit code.

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
- **Cron jobs**: domain re-verification (2 AM), probe staleness detection (3 AM), scan result retention cleanup (4 AM), cert expiry monitoring (6 AM), activation reminder emails (10 AM)

## Writing Style

When generating user-facing content: avoid em dashes, "delve", "leverage", "elevate", "streamline", "robust", "seamless", and other patterns commonly associated with AI-generated text. Write naturally and directly.

## AI Agent Skills

See [tools/](tools/) for structured skill definitions that AI agents can use:

- **[krakenkey-api](tools/krakenkey-api/)** -- Tool definitions and workflows for the KrakenKey REST API, one tool per public route: certificate lifecycle and chain download, domain verification, endpoint monitoring, connected probes, public scan, organizations, users, and billing. OAuth redirects, the Stripe webhook, and `/metrics` are intentionally left out.
- **[krakenkey-cli](tools/krakenkey-cli/)** -- Tool definitions and workflows for the `krakenkey` CLI (v0.4.0). Covers all commands: auth, domain, cert, endpoint, account, and version.

When the API or CLI changes, update the matching `tools/` files in the same release. The definitions are checked against `app` main and the latest `cli` release, so drift shows up as wrong paths or missing flags for agents.
