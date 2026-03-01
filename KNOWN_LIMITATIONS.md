# Known Limitations

This document tracks current limitations and planned improvements in KrakenKey. Items are organized by category and roughly ordered by impact.

---

## Certificate Management

### Auto-renewal threshold is not configurable

Certificates are automatically renewed 30 days before expiry. There is no per-certificate or per-user configuration for this threshold.

### No certificate download endpoint

Issued certificates are returned inline with the certificate record via `GET /certs/tls/:id`. There is no dedicated download endpoint that returns the PEM file directly with appropriate `Content-Type` and `Content-Disposition` headers.

### No real-time status updates

Certificate issuance progress is only available via polling `GET /certs/tls/:id`. There are no WebSocket or Server-Sent Events endpoints for push-based status updates.

---

## Cryptographic Key Support

### Limited ECDSA curve support

Only P-256 and P-384 curves are accepted for ECDSA CSRs. P-521 and other curves are rejected. RSA keys must be >= 2048 bits.

### No Ed25519/Ed448 support

CSRs using EdDSA key types (Ed25519, Ed448) are not supported. Only RSA and ECDSA key algorithms are accepted.

---

## Authentication & Authorization

### No token refresh mechanism

The OIDC login flow does not implement refresh tokens. When the session token expires, the user must re-authenticate through the full login flow.

### No proactive API key expiry cleanup

Expired API keys are rejected at validation time, but there is no background job to notify users about upcoming or recently expired keys.

### Single role model

All authenticated users have identical permissions. There is no role-based access control, organization, or team concept.

**Planned**

---

## Rate Limiting

### All users are on the free tier

The tier-aware rate limiter is fully implemented with multiple tiers, but there is currently no subscription system to assign users to higher tiers.

**Planned**

---

## Domain Verification

### Transient DNS failures can revoke domain verification

Daily re-verification marks a domain as unverified if the TXT record lookup fails, including due to transient DNS errors. There is no retry or grace period.

---

## Notifications

### No email notifications

Users are not notified about certificate expiry, issuance completion, issuance failure, or domain verification changes. All status checks require polling the API or checking the dashboard.

**Planned**

---

## Observability

### No metrics or monitoring

There is no Prometheus metrics endpoint, Grafana dashboard, or alerting. System health is limited to the `/health` endpoint.

**Planned**

---

## Open-Source Contributor Experience

### OAuth login requires a client secret

KrakenKey authenticates via Authentik (OIDC). The OAuth client secret is not included in the repository. Contributors cannot use SSO login without obtaining a secret from a maintainer or setting up their own Authentik instance. See [CONTRIBUTING.md](CONTRIBUTING.md) for workarounds.

**Planned:** A dev auth bypass mode for local development.
