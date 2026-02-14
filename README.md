# KrakenKey

TLS certificate management platform. Submit CSRs, automate ACME issuance via DNS-01 challenges, and manage certificates through a web UI or REST API.

## Workspace Layout

```
KrakenKey/
├── .devcontainer/            ← local dev environment (Docker Compose, Traefik, TLS)
├── .pre-commit-config.yaml   ← pre-commit hooks (secrets detection, YAML/JSON lint)
├── app/                      ← application code (NestJS backend + React frontend)
│   ├── backend/
│   ├── frontend/
│   └── docs/
├── infra/                    ← infrastructure (Docker Compose, Terraform, CI/CD)
│   ├── docker/
│   ├── terraform/
│   └── docs/
├── LOCAL_DEV.md              ← local development setup guide
└── CONTRIBUTING.md           ← contributor guide & known limitations
```

## Getting Started

See [LOCAL_DEV.md](LOCAL_DEV.md) for the full devcontainer setup with TLS, Traefik, and hot reload.

## Documentation

### Development
- [Local Development Setup](LOCAL_DEV.md)
- [Contributing](CONTRIBUTING.md)

### Application
- [Backend Docs](app/backend/docs/README.md) — architecture, API reference, database schema, certificate flow
- [Error Handling](app/docs/ERROR_HANDLING.md)
- [Domain Verification](app/docs/DOMAIN_VERIFICATION_GUIDE.md)

### Infrastructure
- [Infrastructure Overview](infra/README.md)
- [CI/CD & Secrets](infra/docs/CI_CD.md)
- [Docker Deployment](infra/docs/DEPLOYMENT.md)
- [Bitwarden Secrets Setup](infra/docs/BITWARDEN_SETUP.md)
