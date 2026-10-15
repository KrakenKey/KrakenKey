# KrakenKey API Workflows

Common multi-step workflows for AI agents using the KrakenKey API. All paths are relative to the base URL (`https://api.krakenkey.io` in production). Authenticated calls send `Authorization: Bearer <token>`.

## 1. Register and Verify a Domain

A domain needs two DNS records before certificates can be issued for it:

| Record | Name | Value | Checked when |
|--------|------|-------|--------------|
| TXT | the hostname itself (`@` for an apex domain) | the `verificationCode` from the API | `POST /domains/{id}/verify`, and again daily |
| CNAME | `_acme-challenge.<hostname>` | `<hostname with dots replaced by dashes>.acme.krakenkey.io` | every issuance and renewal |

```
Step 1: Register the domain
  POST /domains
  Body: { "hostname": "example.com" }
  Response: { "id": "uuid", "hostname": "example.com",
              "verificationCode": "krakenkey-site-verification=abc123...",
              "isVerified": false, ... }

Step 2: The user creates the DNS records at their DNS provider
  TXT    example.com                    "krakenkey-site-verification=abc123..."
  CNAME  _acme-challenge.example.com    example-com.acme.krakenkey.io

Step 3: Wait for DNS propagation (usually a few minutes)

Step 4: Trigger verification
  POST /domains/{id}/verify
  Success: the domain object with "isVerified": true
  400: "Verification TXT record not found..." or "DNS lookup failed: ..."
       Wait and retry. Verification is in the expensive rate-limit category
       (5/hour on free), so do not poll it in a tight loop.
```

Notes:

- Step 2 happens outside the API. Tell the user exactly which records to create and wait for them to confirm before calling verify.
- Verify only checks the TXT record. The `_acme-challenge` CNAME is not checked until a certificate is requested (see workflow 2).
- Verifying a domain also authorizes its subdomains and wildcards (`www.example.com`, `*.example.com`). Each name you put in a CSR still needs its own `_acme-challenge` CNAME, for example `_acme-challenge.www.example.com CNAME www-example-com.acme.krakenkey.io`. A wildcard uses the base name's record (`*.example.com` uses `_acme-challenge.example.com`).
- A daily job rechecks verified domains and marks a domain unverified if its TXT record disappears. Leave the TXT record in place.
- Registering a hostname the caller already registered returns the existing record. Hitting the plan's domain limit returns 402.

## 2. Issue a Certificate (End-to-End)

Prerequisites: a verified domain covering every name in the CSR, and the `_acme-challenge` CNAME for each of those names.

```
Step 1: Generate a key and CSR locally. The private key never goes to KrakenKey.
  $ openssl req -new -newkey rsa:2048 -nodes \
      -keyout private.key -out request.csr \
      -subj "/CN=example.com" \
      -addext "subjectAltName=DNS:example.com,DNS:www.example.com"
  Allowed keys: RSA 2048 bits or more, or ECDSA P-256 / P-384.

Step 2: Submit the CSR
  POST /certs/tls
  Body: { "csrPem": "<contents of request.csr>" }
  Response (201): { "id": 42, "status": "pending" }

Step 3: Poll until the status is final
  GET /certs/tls/42
  Poll every 15-30 seconds for up to 10 minutes.
  pending -> issuing -> issued   (typically 2-5 minutes)
                    \-> failed

Step 4: Get the certificate for deployment
  GET /certs/tls/42/chain
  Use fullChainPem (leaf + intermediates). See workflow 3.

Step 5 (optional): Parsed details
  GET /certs/tls/42/details
  Returns serialNumber, issuer, subject, validFrom, validTo, keyType, keySize, fingerprint
```

Errors when submitting:

- `400` "No verified domains found..." or "CSR contains unauthorized domains: ...": verify the domain first (workflow 1).
- `400` CSR problems: bad PEM, failed signature check, RSA under 2048 bits, unsupported curve.
- `402` plan limit: concurrent pending requests, total active certificates, or certificates per month.
- `409` an identical CSR is already being submitted. Retry shortly. Resubmitting the same CSR within 15 minutes returns the original certificate's id and status instead of creating a new one, unless that certificate failed or was revoked.

When the status is `failed`:

- `failureReason` on the certificate holds the error from the last failed attempt; it is cleared when the next attempt starts. The account owner also gets a failure email unless they turned off `cert_failed` notifications.
- The most common cause is a missing or wrong `_acme-challenge` CNAME. KrakenKey checks the CNAME before it contacts the CA, and a missing or mismatched record fails the request right away with no retries, with a message naming the exact record to create. Have the user check the CNAME for every name in the CSR, then call `POST /certs/tls/{id}/retry`.
- CA policy refusals (including CAA records that block Let's Encrypt) and CA rate limits also fail immediately. Transient errors are retried automatically (3 attempts in total) before the status becomes `failed`.
- `retry` counts against the same plan limits as a new request. Retrying without fixing a permanent cause fails again.

## 3. Download the Certificate and Full Chain

```
Step 1: Get the chain
  GET /certs/tls/{id}/chain
  Response:
  {
    "leafCert": { "serialNumber": "...", "subject": "...", "validTo": "...", ... },
    "intermediates": [ { "serialNumber": "...", "subject": "...", "issuer": "...",
                         "validFrom": "...", "validTo": "...", "fingerprint": "..." } ],
    "fullChainPem": "-----BEGIN CERTIFICATE-----\n...leaf...\n-----BEGIN CERTIFICATE-----\n...intermediate..."
  }

Step 2: Write the files the server expects
  fullchain.pem  <- fullChainPem              (nginx, Caddy, HAProxy, most servers)
  cert.pem       <- crtPem from GET /certs/tls/{id}    (leaf only)
  chain.pem      <- chainPem from GET /certs/tls/{id}  (intermediates only)
  privkey.pem    <- the key generated in workflow 2, step 1 (never from the API)
```

`/chain` and `/details` return `400` when the certificate has no PEM, which is the case before issuance, after a failed issuance, and after a renewal that failed once the certificate had already expired. A renewal keeps the current certificate readable while it runs, and after it fails as long as the certificate is still valid.

## 4. Renew a Certificate

Certificates with `autoRenew: true` (the default) renew automatically. A daily job queues renewal once a certificate is inside its plan's renewal window: 10 days before expiry on the free plan (called Starter), 30 days on Pro, Business and Enterprise. On the free plan, auto-renewal pauses if the user has not confirmed it in the last 6 months; `POST /auth/confirm-auto-renewal` resets that. Auto-renewal is skipped, and the user notified by email, when the monthly certificate limit is reached.

Manual renewal:

```
Step 1: Note the current certificate
  GET /certs/tls/{id}
  Keep crtPem to compare later. It stays readable while the renewal runs,
  and stays in place if the renewal fails.

Step 2: Trigger renewal (status must be "issued", otherwise 400)
  POST /certs/tls/{id}/renew
  Response 201: { "id": 42, "status": "renewing", "skipped": false, "queued": false }
  Response 202: same with "queued": true when the account's concurrent pending
  slots are full; it starts on its own as earlier requests finish. Don't call
  renew again; just poll.

Step 3: Poll until the status is no longer "renewing"
  GET /certs/tls/{id}
  issued, new crtPem                  -> renewed
  issued, renewalFailedAt set         -> renewal failed; the old certificate
                                         is still in place, failureReason says why
  failed                              -> renewal failed and the old
                                         certificate had already expired

Step 4: Fetch and deploy the new chain (workflow 3)
```

Without a body, renewal reuses the stored CSR, so the key pair stays the same. To rotate the key, send a new CSR with exactly the certificate's names: `POST /certs/tls/{id}/renew` with `{ "csrPem": "..." }` (a different set of names returns `400`). Either way it needs the same `_acme-challenge` CNAMEs as issuance. A renewal is never refused for a plan limit: it doesn't count toward the monthly or issued certificate limits, and past the concurrent pending limit it waits (`202`, `renewalQueuedAt` set on the certificate) instead of failing. While a renewal runs or waits, renew returns `409`; with `?ifDue=true` it returns `200` with `{ "skipped": true, "reason": "in_progress", "queued": ... }` instead, so a scheduled job doesn't fail (`krakenkey cert renew --if-due` exits 0 on it). A certificate whose renewal is still waiting can be revoked; the waiting renewal is dropped. If a request's job is lost, it is recovered after 30 minutes: a renewal goes back into the queue (at most twice; the third time it loses its job it is recorded as a failed renewal), a new certificate to `failed` with a `failureReason`, so retry works.

When a renewal fails while the current certificate is still valid, the certificate stays `issued` with its PEM, chain and expiry, `renewalFailedAt` is set and `failureReason` says why; if the renewal used a new CSR, the CSR of the kept certificate is put back, so send the new CSR again when you retry (the owner gets a "renewal failed" email and a `cert.failed` alert with `renewal: true`). Downloads, expiry alerts and ARI checks keep working. Fix the cause (usually the `_acme-challenge` CNAME or a CAA record), then call `POST /certs/tls/{id}/renew` or `POST /certs/tls/{id}/retry`; both renew right away and clear the failure. Automatic renewal tries again on its own once the certificate is due: the next automatic attempt is not before 20 hours after the failure, or a quarter of the time left until expiry (or the end of a CA early-replacement window) when that is sooner, but at least 2 hours after it. `renewAfter` shows that time, and `?ifDue=true` returns `200` `{ "skipped": true, "reason": "not_due", "retryAfter": ... }` until then. A renewal that fails after the certificate expired ends `failed` with no PEM, like a failed issuance.

`?ifDue=true` renews only when the certificate is due and otherwise returns `200` with `{ "skipped": true, "reason": "not_due", ... }`, which makes it safe to call from a scheduled job. Every certificate reports `renewAfter`, the time it will be renewed: expiry minus the plan window, moved earlier if the CA asked for early replacement (ARI).

Certificates renewed by a customer-hosted connector are marked `PATCH /certs/tls/{id}` with `{ "managedBy": "connector" }`. KrakenKey then never renews them itself; the connector renews them with its own keys once `renewAfter` passes. For these certificates `renewAfter` uses a window of at least 30 days and follows the CA's suggested renewal window.

To turn auto-renewal off: `PATCH /certs/tls/{id}` with `{ "autoRenew": false }`.

## 5. Revoke and Delete a Certificate

```
Step 1: Revoke (status must be "issued", otherwise 400)
  POST /certs/tls/{id}/revoke
  Body: { "reason": 4 }
    0=unspecified (default), 1=keyCompromise, 3=affiliationChanged,
    4=superseded, 5=cessationOfOperation
  Response: { "id": 42, "status": "revoked" }

Step 2 (optional): Delete the record
  DELETE /certs/tls/{id}
  Response: { "id": 42 }
```

Revocation is synchronous: the response already says `revoked`. If the CA call fails the API returns `500` and the certificate stays `issued`. Only the user who created a certificate can revoke it; other org members get `404`. Delete only works on `failed` or `revoked` certificates.

## 6. Create an API Key

```
Step 1: Create the key
  POST /auth/api-keys
  Body: { "name": "my-ci-key", "expiresAt": "2027-01-01T00:00:00Z" }   (both optional)
  Response: { "apiKey": "kk_abc123...", "id": "uuid", "name": "my-ci-key" }

  The apiKey value is returned only once. Store it immediately.

Step 2: Use it
  Authorization: Bearer kk_abc123...
```

A JWT from the web login or an existing API key can create keys. Hitting the plan's API key limit returns 402. Expired keys get `401`, and the key's owner may get an email warning that an expired key was used. Repeated invalid keys from one IP lock that IP out of API key auth for a while (`429`).

### Without any credential: browser login

An agent or tool with no key can ask the user to approve one in the browser (OAuth device flow, RFC 8628):

```
POST /auth/device/code
Body: { "clientName": "build-01" }
→ { "deviceCode", "userCode": "BCDF-GHJK", "verificationUriComplete", "expiresIn": 600, "interval": 5 }

# Send the user verificationUriComplete and userCode. Then, every `interval` seconds:
POST /auth/device/token
Body: { "deviceCode": "..." }
→ { "status": "pending" }   (keep polling; "slow_down" means wait 5 seconds longer)
→ { "status": "approved", "apiKey": "kk_...", "id": "...", "name": "CLI login: build-01" }
→ { "status": "denied" } or { "status": "expired" }   (stop)
```

The key is created by the poll that finds the login approved and is returned only once. Approval itself needs a dashboard session, so an agent can't approve its own login.

## 7. Set Up Endpoint Monitoring

Endpoints are scanned by probes. There are two ways to get scans:

- **Hosted probes** (every plan; 1 hosted endpoint on the free plan, 25 on Pro, 150 on Business): KrakenKey-operated probes in a region (`us-east-1` today). They scan every 60 minutes on the free plan, 30 on Pro, 5 on Business and 1 on Enterprise.
- **Connected probes** (all plans): a `krakenkey-probe` the user runs, authenticated with a `kk_` API key. The API accepts their results at most once per 60 minutes on the free plan, 15 on Pro and 1 on Business and Enterprise per endpoint; faster results are skipped.

```
Step 1: Create the endpoint
  POST /endpoints
  Body: { "host": "example.com", "port": 443, "label": "Production API" }
  Response: the endpoint, with an immediate scan requested.
  Creating the same host and port again updates and returns the existing endpoint.
  403 when the monitored endpoint limit is reached.

Step 2a (hosted): Add a region
  POST /endpoints/{id}/regions
  Body: { "region": "us-east-1" }
  403 with code plan_limit_exceeded when the hosted endpoint or hosted region limit is reached
  (the free plan allows one endpoint in one region).

Step 2b (connected): Assign the user's probe
  GET /endpoints/probes/mine           -> pick a probe id
  POST /endpoints/{id}/probes
  Body: { "probeIds": ["<probe id>"] }
  A connected probe only scans endpoints assigned to it. See workflow 9 for probe setup.

Step 3: Check results
  GET /endpoints/{id}/results/latest
  Latest result from each probe: connectionSuccess, latencyMs, tlsVersion,
  certDaysUntilExpiry, certTrusted, probeMode, probeRegion, scannedAt

  GET /endpoints/{id}/results?page=1&limit=20     (limit max 100)
  Paginated history, newest first: { "data": [...], "total": 123 }

  GET /endpoints/{id}/results/export?format=csv   (or json)
  All stored results as a file
```

Steps 2a and 2b can also be done in step 1 with `hostedRegions` and `probeIds` in the create body.

## 8. Manage Monitored Endpoints

```
# Request a scan now (probes see it the next time they fetch config, within 5 minutes).
# Once per plan interval (60, 15 or 1 minutes; the hosted interval when the endpoint
# has a hosted region and it is longer). Sooner returns 429 saying when to try again.
POST /endpoints/{id}/scan

# Pause or resume monitoring (inactive endpoints are not given to probes)
PATCH /endpoints/{id}
Body: { "isActive": false }

# Change label or SNI
PATCH /endpoints/{id}
Body: { "label": "API (blue)", "sni": "api.example.com" }

# Replace all hosted regions or probe assignments at once
PATCH /endpoints/{id}
Body: { "hostedRegions": ["us-east-1"], "probeIds": [] }

# Remove one region or one probe
DELETE /endpoints/{id}/regions/us-east-1
DELETE /endpoints/{id}/probes/{probeId}

# Delete the endpoint (scan history is kept but unlinked)
DELETE /endpoints/{id}
```

Scan results older than the plan's retention period (7 days on free, 30 on Pro, 90 on Business and Enterprise) are deleted daily.

## 9. Connected Probe (Self-Hosted)

What the probe does with the API. Useful when debugging a probe or writing a custom one.

```
# 1. The user creates an API key for the probe (workflow 6)

# 2. The probe registers. Registering again with the same probeId is a heartbeat
POST /probes/register        Authorization: Bearer kk_...
Body: { "probeId": "<stable id>", "name": "office-probe", "version": "x.y.z",
        "mode": "connected", "os": "linux", "arch": "amd64" }

# 3. The user assigns the probe to endpoints (workflow 7, step 2b)

# 4. The probe fetches its work list
GET /probes/{probeId}/config
Response: { "endpoints": [ { "host": "example.com", "port": 443, "sni": "example.com",
                             "userId": "...", "scanNow": true } ],
            "interval": "60m" }
Only active endpoints assigned to this probe are returned.

# 5. The probe reports results
POST /probes/report
Body: { "probeId": "...", "mode": "connected", "timestamp": "2026-10-02T12:00:00Z",
        "results": [ { "endpoint": { "host": "example.com", "port": 443 },
                       "connection": { "success": true, "tlsVersion": "TLS 1.3", "latencyMs": 42 },
                       "certificate": { "subject": "CN=example.com", "daysUntilExpiry": 61,
                                        "trusted": true } } ] }
Response: { "accepted": 1 }
```

Results are matched to the caller's endpoints by host and port. Unmatched results are skipped, so `accepted` can be lower than the number sent. A probe that has not registered or reported in 24 hours is marked `stale` by a daily job; the next register call sets it back to `active`. Probe routes also accept `kk_svc_` service keys, which are only issued for KrakenKey's hosted probes.

## 10. Quick TLS Check Without an Account

```
POST /public-scan
Body: { "hostname": "example.com", "port": 443 }     (port: 443 or 8443, default 443)
Response (200):
{
  "endpoint": { "host": "example.com", "port": 443, "sni": "example.com" },
  "connection": { "success": true, "tlsVersion": "...", "cipherSuite": "...", "latencyMs": 38 },
  "certificate": { "subject": "...", "issuer": "...", "notAfter": "...",
                   "daysUntilExpiry": 61, "trusted": true, "chainComplete": true, ... },
  "scannedAt": "2026-10-02T12:00:00.000Z"
}
```

No auth needed. Rate limited in the `public` category (30/min per IP when unauthenticated). Returns `400` for raw IPs, names that do not resolve, or names that resolve to private or reserved addresses, and `503` when the scanner is unavailable. Results are not stored; use workflow 7 for ongoing monitoring.

## 11. Organizations

Organizations are managed in the dashboard (Organizations page). With an API key an agent can only read one:

```
# Read, including members
GET /organizations/{id}
```

Creating, renaming, and dissolving an organization, inviting and removing members, changing roles, and transferring ownership return `403` to API keys. Creating one needs the Pro plan or higher (`402` on the free plan). Pro allows 3 members, owner included; Business and Enterprise have no member limit. Members share domains, certificates, and endpoints, and plan limits are counted across all members.

## 12. Subscription and Upgrades

Plan ids are `free`, `pro`, `business` and `enterprise`. The free plan is shown as "Starter" in the dashboard and in API messages. Pro and Business are billed monthly or yearly (a year costs ten months); Enterprise is sold by quote.

```
# Current plan (users with no subscription get plan "free", status "active")
GET /billing/subscription
Response includes "interval": "month" | "year" for a Stripe subscription,
null on the free plan and for Microsoft Marketplace subscriptions

# Plans and intervals that can be bought here
GET /billing/plans
Response: { "plans": [ { "plan": "pro", "intervals": ["month", "year"] },
                       { "plan": "business", "intervals": ["month", "year"] } ] }

# Paid -> higher paid plan: preview the charge
POST /billing/upgrade/preview
Body: { "plan": "business", "interval": "year" }     (interval defaults to the current one)
Response: { "immediateAmountCents": 120000, "currency": "usd", "targetPlan": "business",
            "targetInterval": "year", "currentPeriodEnd": "...", "prorationDate": 1791000000 }
```

The preview is Stripe's own calculation of the upgrade: the new price for the rest of the period less the unused time on the current plan, charged at once. Changing the interval as part of the upgrade starts a new billing period that day.

Checkout, upgrade, and the Stripe portal return `403` to API keys. To change plan, send the user to the Billing page in the dashboard; downgrades and switching between monthly and yearly billing also happen there, through the Stripe portal. Preview returns `404` without an active paid subscription, `400` if the target plan is not higher than the current one or can't be bought, and `409` for a subscription billed through Microsoft Marketplace. In an organization only the owner can use billing (`403` for other members).

## Plan Limits

| Resource | Free (Starter) | Pro | Business | Enterprise |
|----------|----------------|-----|----------|------------|
| Domains | 3 | 15 | 100 | custom |
| API keys | 2 | 10 | 50 | custom |
| Certificates created per calendar month (UTC) | 5 | 100 | 1,000 | custom |
| Issued certificates | 10 | 150 | 1,000 | custom |
| Concurrent pending/issuing/renewing (renewals past it wait instead of failing) | 2 | 10 | 50 | custom |
| Auto-renewal window (days before expiry) | 10 | 30 | 30 | 30 |
| Monitored endpoints | 3 | 50 | 300 | custom |
| Hosted regions (total across endpoints) | 1 | all | all | all |
| Endpoints with hosted monitoring | 1 | 25 | 150 | custom |
| Hosted scan interval (minutes) | 60 | 30 | 5 | 1 |
| Shortest connected probe interval (minutes) | 60 | 15 | 1 | 1 |
| Scan result retention (days) | 7 | 30 | 90 | 90 |
| Hosts per portfolio report | 25 | 250 | 1,000 | 1,000 |
| Connectors (not revoked) | 1 | 5 | 50 | custom |
| Alert channels | 1 | 5 | 25 | custom |
| GitHub OIDC trust policies | 2 | 10 | 50 | custom |
| Organization members (owner included) | no organizations | 3 | unlimited | unlimited |

Limits are counted across all members of an organization. Going over a limit, for example after a downgrade, never removes anything; only creating another resource is refused.

## Error Handling

Errors use this format:

```json
{
  "statusCode": 400,
  "message": "Verification TXT record not found. Please ensure the record has propagated and try again.",
  "error": "Bad Request",
  "timestamp": "2026-10-02T10:30:00.000Z",
  "path": "/domains/3f6c.../verify"
}
```

`message` is an array of strings for request validation errors (one entry per failed field). Unknown body fields are stripped silently.

Status codes to handle:

- `400`: fix the request. Validation errors, or the resource is in the wrong state (for example renewing a certificate that is not `issued`). Read `message`.
- `401`: missing, invalid, or expired token or API key. Do not retry with the same credentials.
- `402`: plan limit reached (domains, API keys, certificate limits, connectors, alert channels, GitHub trust policies, organization members; never for a renewal) or a feature that needs a higher plan (organizations). `message` names the limit, for example "Monthly certificate limit reached". Tell the user; retrying will not help until they upgrade or free up capacity.
- `403`: not allowed. A dashboard-only action called with an API key ("API keys cannot be used for this action"; see the README), endpoint, hosted-endpoint and hosted-region plan limits ("Endpoint limit reached", "Hosted endpoint limit reached"), too many hosts in a report, org role checks, billing outside the org owner, or admin-only routes.
- `404`: the resource does not exist or the caller cannot see it.
- `409`: conflict. Duplicate certificate request still in progress, a renewal of the certificate already running or waiting (or another renew request won the race), a revoke that lost a race, already in an organization, the organization is dissolving, or another request for the same account was creating a limited resource at the same moment (retry once).
- `429`: rate limited. Wait for the number of seconds in the `Retry-After` response header before retrying. Also returned after too many invalid API key attempts from one IP, and by `POST /endpoints/{id}/scan` within the plan's scan interval (the message says when to try again).
- `500`: server or CA error. For revocation, the certificate stays `issued`; retry later.
- `503`: dependency unavailable (readiness check, public scan).

Plan limit responses (`402` or `403`) add `code: "plan_limit_exceeded"` and, where they apply, `limit`, `current`, `plan` (the plan id) and `upgradeTo` (the next plan up, `enterprise` from Business):

```json
{
  "statusCode": 402,
  "message": "Alert channel limit reached: the Starter plan includes 1. Upgrade to Pro for 5.",
  "error": "Payment Required",
  "timestamp": "2026-10-14T10:30:00.000Z",
  "path": "/notifications/channels",
  "code": "plan_limit_exceeded",
  "limit": 1,
  "current": 1,
  "plan": "free",
  "upgradeTo": "pro"
}
```

## Rate Limiting

Limits depend on the plan and the route category. Each tool in `tool-definitions.json` has a `rate_limit_category`.

| Plan | public | read | write | expensive | renewal |
|------|--------|------|-------|-----------|---------|
| free | 30/min | 60/min | 20/min | 5/hour | 10/hour |
| pro | 60/min | 300/min | 60/min | 30/hour | 120/hour |
| business | 120/min | 600/min | 120/min | 60/hour | 300/hour |
| enterprise | 120/min | 1000/min | 200/min | 100/hour | 600/hour |

How it is applied:

- Each route has its own counter. Five certificate requests per hour on free does not use up the ten renewals or five domain verifications. `ifDue=true` renew calls count even when nothing is due.
- Requests with a JWT are counted per user at the user's plan.
- Requests with a user `kk_` API key are counted against the key's owner at the owner's plan, so all of a user's keys share one counter.
- Service keys, unknown keys, unauthenticated requests and every request to a public route are counted per client IP at the free-plan limits.
- Windows are fixed. Exceeding a limit blocks that route for one full window (one minute, or one hour for `expensive` and `renewal`).
- Successful responses include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset`. A `429` includes `Retry-After` in seconds.

Polling guidance: poll `GET /certs/tls/{id}` every 15-30 seconds (a `read` route). Never poll `verify`, `renew`, `retry`, `revoke`, or `POST /certs/tls`; they are `expensive` or `renewal` routes with hourly limits.
