<p align="center">
  <h1 align="center">KrakenKey</h1>
  <p align="center">
    Automated TLS certificate management via ACME DNS-01 challenges.
    <br />
    <a href="https://krakenkey.io">Website</a> &middot;
    <a href="https://app.krakenkey.io">Dashboard</a> &middot;
    <a href="app/backend/docs/API_REFERENCE.md">API Reference</a> &middot;
    <a href="https://github.com/krakenkey/krakenkey/discussions">Discussions</a>
  </p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="License: AGPL-3.0"></a>
  <a href="https://krakenkey.io"><img src="https://img.shields.io/badge/status-early%20access-orange.svg" alt="Status: Early Access"></a>
  <a href="https://krakenkey.io"><img src="https://img.shields.io/badge/website-krakenkey.io-06b6d4.svg" alt="Website"></a>
</p>

## What is KrakenKey?

KrakenKey is a TLS certificate management platform that automates issuance via Let's Encrypt using DNS-01 challenges. One-time DNS setup per domain, then certificates in ~4 minutes -- no ongoing records to manage, no cron jobs, no forgotten renewals.

Private keys never leave your device. CSRs are generated client-side using the WebCrypto API, or you bring your own from `openssl`. KrakenKey only ever sees your public key.

**Works with any DNS provider.** Add a TXT record and a CNAME at your registrar -- Cloudflare, Route 53, Namecheap, DigitalOcean, whatever you use. KrakenKey handles ACME challenges on its own infrastructure.

**Why now?** The CA/Browser Forum's [Ballot SC-081v3](https://cabforum.org/2025/04/08/ballot-sc-081v3-introduce-schedule-of-reducing-validity-and-data-reuse-periods/) is phasing TLS certificate max lifetimes down to 47 days by March 2029. Manual renewal won't scale.

## Features

- **Client-side CSR generation** -- WebCrypto API in the browser; private keys stay on your device
- **ACME automation** -- Let's Encrypt certificate issuance via DNS-01 challenges
- **DNS provider agnostic** -- one-time CNAME delegation; works with any registrar
- **REST API** -- every dashboard action is available programmatically
- **Web dashboard** -- visual certificate lifecycle management
- **Domain verification** -- DNS TXT record ownership proof with daily re-verification
- **Auto-renewal monitoring** -- daily expiry checks, automatic renewal at 30 days
- **API key authentication** -- persistent keys for CI/CD and automation workflows
- **Tier-aware rate limiting** -- configurable per-tier throttling on all endpoints
- **Swagger/OpenAPI docs** -- interactive API documentation

## How It Works

**One-time setup per domain:**

1. Add your domain in the dashboard and configure two DNS records: a **TXT** record for ownership verification and a **CNAME** to delegate ACME challenges to KrakenKey

**Per certificate (~4 minutes):**

2. **Generate a CSR** -- in-browser via the dashboard or with `openssl` on your machine
3. **Submit** via the dashboard or REST API
4. **Download your certificate** -- KrakenKey resolves the ACME challenge automatically and issues the cert

## Quick Start

### Use the managed service

Head to [krakenkey.io](https://krakenkey.io) and create a free account. No credit card required.

### Contribute / run locally

```bash
git clone --recurse-submodules https://github.com/krakenkey/krakenkey.git
cd krakenkey
code .  # Reopen in Dev Container when prompted
```

See [LOCAL_DEV.md](LOCAL_DEV.md) for the full devcontainer setup with TLS, Traefik, and hot reload. See [CONTRIBUTING.md](CONTRIBUTING.md) for the contributor guide.

## API Example

```bash
# Add a domain
curl -X POST https://api.krakenkey.io/domains \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"hostname": "example.com"}'

# Submit a CSR
curl -X POST https://api.krakenkey.io/certs/tls \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"csrPem": "-----BEGIN CERTIFICATE REQUEST-----\n...\n-----END CERTIFICATE REQUEST-----"}'

# Check status / retrieve certificate
curl https://api.krakenkey.io/certs/tls/42 \
  -H "Authorization: Bearer $API_KEY"

# Renew
curl -X POST https://api.krakenkey.io/certs/tls/42/renew \
  -H "Authorization: Bearer $API_KEY"
```

See the full [API Reference](app/backend/docs/API_REFERENCE.md) for all endpoints, authentication, error formats, and more examples.

## Architecture

```
Browser / CLI
      |
      v
  NestJS REST API
      |
      +---> PostgreSQL (certs, domains, users)
      +---> Redis / BullMQ (async job queue)
      +---> ACME Client (Let's Encrypt)
      +---> DNS (challenge resolution on KrakenKey infra)
```

Certificate issuance is asynchronous. Submitting a CSR enqueues a BullMQ job that handles the ACME flow (create order, set DNS challenge, poll propagation, finalize) and stores the issued certificate. Jobs retry with exponential backoff on failure.

### Tech Stack

| Component | Technology |
|-----------|-----------|
| Backend | NestJS 11, TypeScript |
| Frontend | React 19, TypeScript, Vite |
| Database | PostgreSQL, TypeORM |
| Job Queue | BullMQ (Redis) |
| ACME Client | acme-client |
| CSR Generation | WebCrypto API, @peculiar/x509 |
| Authentication | Authentik (OIDC) + API Keys |
| API Documentation | Swagger / OpenAPI |
| Marketing Site | Astro |

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](app/backend/docs/ARCHITECTURE.md) | System design, module hierarchy, data flow |
| [API Reference](app/backend/docs/API_REFERENCE.md) | All endpoints, auth, error formats, examples |
| [Certificate Flow](app/backend/docs/CERTIFICATE_FLOW.md) | CSR submission through issuance, step by step |
| [Database Schema](app/backend/docs/DATABASE.md) | Entities, relationships, migrations |
| [Configuration](app/backend/docs/CONFIGURATION.md) | Environment variables and setup |
| [Integrations](app/backend/docs/INTEGRATIONS.md) | ACME and DNS provider integration details |
| [Rate Limiting](app/backend/docs/RATE_LIMITS.md) | Tier configuration and throttling behavior |
| [Domain Verification](app/docs/DOMAIN_VERIFICATION_GUIDE.md) | Setup guide with DNS examples |
| [Error Handling](app/docs/ERROR_HANDLING.md) | Error format, frontend toast system |
| [Known Limitations](KNOWN_LIMITATIONS.md) | Current constraints and planned improvements |
| [Local Development](LOCAL_DEV.md) | Devcontainer setup, TLS, Traefik |

## Contributing

We welcome bug reports, feature requests, and pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, testing instructions, and the PR process.

## Security

To report a vulnerability, see [SECURITY.md](SECURITY.md). Please do **not** open a public issue for security concerns.

## License

KrakenKey is licensed under the [GNU Affero General Public License v3.0](LICENSE).

If you modify KrakenKey and make it available over a network (e.g., as a hosted service), you must make your source code available under the same license.
