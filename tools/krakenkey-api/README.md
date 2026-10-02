# KrakenKey API Skill for AI Agents

Structured tool definitions for AI agents to work with the KrakenKey REST API.

## Files

- `tool-definitions.json`: machine-readable tool definitions with parameters, auth requirements, rate limit category, and response shapes. Works with the function-calling / tool-use formats most LLM frameworks use.
- `workflows.md`: multi-step workflows (verify a domain, issue and renew certificates, download the full chain, set up monitoring, run a public scan, manage orgs and billing), plus error handling, plan limits, and rate limits.

## Base URLs

| Environment | URL |
|-------------|-----|
| Production | `https://api.krakenkey.io` |
| Development | `https://api-dev.krakenkey.io` |

Paths have no prefix or version segment (for example `GET https://api.krakenkey.io/domains`).

## Authentication

Protected routes take a bearer token:

```
Authorization: Bearer <token>
```

| Token | Format | Where it comes from | Accepted on |
|-------|--------|---------------------|-------------|
| User API key | `kk_...` | `POST /auth/api-keys` (shown once) | All authenticated routes |
| JWT | OIDC access token | Browser login through Authentik (web app) | All authenticated routes |
| Service key | `kk_svc_...` | Issued by KrakenKey for its hosted probes | Probe routes only: `/probes/register`, `/probes/report`, `/probes/{probeId}/config` |

The probe routes accept any of the three ("dual" auth in the tool definitions). Every other authenticated route accepts a user API key or a JWT and rejects service keys.

`GET /users` is admin only: the caller must be in the `authentik Admins` group. `GET`, `PATCH`, and `DELETE /users/{id}` work on the caller's own record, or any record for admins.

Agents should use a user API key. Expired keys return `401`. Repeated invalid keys from one IP lock that IP out of API key auth for a period (`429`).

## OpenAPI

The live OpenAPI document is always served at `GET /swagger-json` (for example `https://api.krakenkey.io/swagger-json`). The interactive Swagger UI at `/swagger` is only enabled in development. These tool definitions are a hand-maintained, agent-oriented view of the same API; when they disagree, the running API wins.

## Rate Limits

Limits depend on the user's plan and the route's category (`rate_limit_category` on each tool).

| Plan | public | read | write | expensive |
|------|--------|------|-------|-----------|
| free | 30/min | 60/min | 20/min | 5/hour |
| starter | 60/min | 120/min | 40/min | 10/hour |
| team | 60/min | 300/min | 60/min | 30/hour |
| business | 120/min | 600/min | 120/min | 60/hour |
| enterprise | 120/min | 1000/min | 200/min | 100/hour |

`expensive` routes: certificate issuance, renewal, retry, and revocation, and domain verification. Counters are per route. Requests authenticated with a JWT are counted per user at the user's plan; requests with a `kk_` API key and unauthenticated requests are counted per client IP at the free-plan limits. A `429` response carries a `Retry-After` header in seconds. See `workflows.md` for details.

## Coverage

| Area | Tools |
|------|-------|
| Health and status | `get_api_status`, `liveness_check`, `health_check` |
| Profile and API keys | `get_profile`, `update_profile`, `confirm_auto_renewal`, `list_api_keys`, `create_api_key`, `delete_api_key` |
| Domains | `list_domains`, `register_domain`, `get_domain`, `verify_domain`, `delete_domain` |
| Certificates | `list_certificates`, `submit_csr`, `get_certificate`, `get_certificate_details`, `get_certificate_chain`, `update_certificate`, `renew_certificate`, `retry_certificate`, `revoke_certificate`, `delete_certificate` |
| Endpoints | `list_endpoints`, `create_endpoint`, `get_endpoint`, `update_endpoint`, `delete_endpoint`, `request_endpoint_scan`, `list_my_probes`, `assign_probes`, `unassign_probe`, `add_hosted_region`, `remove_hosted_region`, `get_endpoint_results`, `get_endpoint_latest_results`, `export_endpoint_results` |
| Probes | `register_probe`, `submit_probe_report`, `get_probe_config` |
| Public scan | `public_scan` |
| Feedback | `submit_feedback` |
| Organizations | `create_organization`, `get_organization`, `update_organization`, `delete_organization`, `invite_member`, `update_member_role`, `remove_member`, `transfer_ownership` |
| Billing | `create_checkout_session`, `get_subscription`, `create_billing_portal_session`, `preview_upgrade`, `upgrade_plan` |
| Users | `list_users`, `get_user`, `update_user`, `delete_user` |

60 tools in total.

## Intentionally Not Covered

These routes exist but are not useful to agents, so they have no tool definition:

| Route | Why |
|-------|-----|
| `GET /auth/login`, `GET /auth/register` | Browser redirects into the Authentik sign-in and sign-up flows |
| `GET /auth/callback` | OAuth callback; needs the state cookie set during the browser redirect |
| `POST /billing/webhook` | Stripe webhook; requires a Stripe signature |
| `GET /metrics` | Prometheus scrape endpoint for operators |
| `GET /swagger-json`, `GET /swagger` | API documentation (see OpenAPI above) |
