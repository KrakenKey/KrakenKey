# KrakenKey API Skill for AI Agents

Structured tool definitions for AI agents to work with the KrakenKey REST API.

## Files

- `tool-definitions.json`: machine-readable tool definitions with parameters, auth requirements, rate limit category, and response shapes. Works with the function-calling / tool-use formats most LLM frameworks use.
- `workflows.md`: multi-step workflows (verify a domain, issue and renew certificates, download the full chain, set up monitoring, run a public scan, read org and billing state), plus error handling, plan limits, and rate limits.

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
| User API key | `kk_...` | The dashboard (API Keys), or the browser login flow in `workflows.md` | All authenticated routes except the dashboard-only ones below |
| JWT | OIDC access token | Browser login through Authentik (web app) | All authenticated routes, including dashboard-only |
| Service key | `kk_svc_...` | Issued by KrakenKey for its hosted probes | Probe routes only: `/probes/register`, `/probes/report`, `/probes/{probeId}/config` |

The probe routes accept any of the three ("dual" auth in the tool definitions). Every other authenticated route accepts a user API key or a JWT and rejects service keys.

`GET /users` is admin only: the caller must be in the `authentik Admins` group. `GET /users/{id}` works on the caller's own record, or any record for admins. A request made with an API key is never treated as admin.

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

`expensive` routes: certificate issuance, renewal, retry, and revocation, and domain verification. Counters are per route. Requests with a JWT or a user `kk_` API key are counted per user at the user's plan (all of a user's keys share one counter); service keys, unauthenticated requests and public routes are counted per client IP at the free-plan limits. A `429` response carries a `Retry-After` header in seconds. See `workflows.md` for details.

## Coverage

| Area | Tools |
|------|-------|
| Health and status | `get_api_status`, `liveness_check`, `health_check` |
| Profile and API keys | `get_profile`, `update_profile`, `confirm_auto_renewal`, `list_api_keys` |
| Browser login | `start_device_login`, `poll_device_login` |
| Domains | `list_domains`, `register_domain`, `get_domain`, `verify_domain`, `delete_domain` |
| Certificates | `list_certificates`, `submit_csr`, `get_certificate`, `get_certificate_details`, `get_certificate_chain`, `update_certificate`, `renew_certificate`, `retry_certificate`, `revoke_certificate`, `delete_certificate` |
| Connectors | `list_connectors`, `get_connector`, `list_certificate_deployments` |
| Endpoints | `list_endpoints`, `create_endpoint`, `get_endpoint`, `update_endpoint`, `delete_endpoint`, `request_endpoint_scan`, `list_my_probes`, `assign_probes`, `unassign_probe`, `add_hosted_region`, `remove_hosted_region`, `get_endpoint_results`, `get_endpoint_latest_results`, `export_endpoint_results` |
| Probes | `register_probe`, `submit_probe_report`, `get_probe_config` |
| Public scan | `public_scan` |
| Feedback | `submit_feedback` |
| Organizations | `get_organization` |
| Billing | `get_subscription`, `preview_upgrade` |
| Users | `list_users`, `get_user` |

48 tools in total.

## Dashboard Only

These routes refuse API keys with a `403` ("API keys cannot be used for this action. Sign in to the dashboard instead."), so they have no tool definition. A leaked key can't mint new keys, take over the account, or change the organization or billing. When a task needs one of them, tell the user what to do in the dashboard at app.krakenkey.io.

| Route | Dashboard page |
|-------|----------------|
| `POST /auth/api-keys`, `DELETE /auth/api-keys/{id}` | API Keys. To give a machine its own key, run the browser login flow there instead |
| `GET /auth/device/{userCode}`, `POST /auth/device/approve`, `POST /auth/device/deny` | The approval page linked from `start_device_login` (an agent can't approve its own login) |
| `PATCH /users/{id}`, `DELETE /users/{id}` | Settings |
| `POST /organizations`, `PATCH` and `DELETE /organizations/{id}`, `POST /organizations/{id}/members`, `PATCH` and `DELETE /organizations/{id}/members/{userId}`, `POST /organizations/{id}/transfer-ownership` | Organizations |
| `POST /billing/checkout`, `POST /billing/portal`, `POST /billing/upgrade` | Billing |

## Intentionally Not Covered

These routes exist but are not useful to agents, so they have no tool definition:

| Route | Why |
|-------|-----|
| `GET /auth/login`, `GET /auth/register` | Browser redirects into the Authentik sign-in and sign-up flows |
| `GET /auth/callback` | OAuth callback; needs the state cookie set during the browser redirect |
| `POST /billing/webhook` | Stripe webhook; requires a Stripe signature |
| `GET /metrics` | Prometheus scrape endpoint for operators |
| `GET /swagger-json`, `GET /swagger` | API documentation (see OpenAPI above) |
