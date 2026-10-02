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

- The API does not expose the failure reason. The account owner receives a failure email (unless they turned off `cert_failed` notifications) containing the error.
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

`/chain` and `/details` return `400` when the certificate has no PEM, which is the case before issuance, while a renewal is running, and after a failure.

## 4. Renew a Certificate

Certificates with `autoRenew: true` (the default) renew automatically. A daily job queues renewal once a certificate is inside its plan's renewal window: 5 days before expiry on free, 30 days on paid plans. On the free plan, auto-renewal pauses if the user has not confirmed it in the last 6 months; `POST /auth/confirm-auto-renewal` resets that. Auto-renewal is skipped, and the user notified by email, when the monthly certificate limit is reached.

Manual renewal:

```
Step 1: Save the current certificate if it is still in use
  GET /certs/tls/{id}/chain
  crtPem and chainPem are cleared while the renewal runs, and stay empty if it fails.

Step 2: Trigger renewal (status must be "issued", otherwise 400)
  POST /certs/tls/{id}/renew
  Response: { "id": 42, "status": "renewing" }

Step 3: Poll until the status is "issued" again (or "failed")
  GET /certs/tls/{id}

Step 4: Fetch and deploy the new chain (workflow 3)
```

Renewal reuses the original CSR, so the key pair stays the same. It is checked against the same plan limits as issuance (402) and needs the same `_acme-challenge` CNAMEs. To rotate the key, generate a new CSR and submit it as a new certificate.

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

## 7. Set Up Endpoint Monitoring

Endpoints are scanned by probes. There are two ways to get scans:

- **Hosted probes** (Starter plan and up): KrakenKey-operated probes in a region.
- **Connected probes** (all plans): a `krakenkey-probe` the user runs, authenticated with a `kk_` API key.

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
  403 on the free plan, or when the hosted endpoint or hosted region limit is reached.

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
# Request a scan now (probes see it the next time they fetch config, within 5 minutes)
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

Scan results older than the plan's retention period (5 days on free, 30 on Starter, 90 on Team and up) are deleted daily.

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

Creating an organization requires a Team plan or higher (402 otherwise). Members share domains, certificates, and endpoints, and plan limits are counted across all members.

```
# Create (caller becomes owner; 409 if already in an org)
POST /organizations
Body: { "name": "My Team" }

# Read, including members
GET /organizations/{id}

# Rename (owner or admin)
PATCH /organizations/{id}
Body: { "name": "Platform Team" }

# Add an existing user by email (owner or admin)
# 404 if they never logged in; 409 if they are in another org or have an active paid plan
POST /organizations/{id}/members
Body: { "email": "colleague@example.com", "role": "member" }    (admin | member | viewer)

# Change a role (owner or admin; not the owner's role)
PATCH /organizations/{id}/members/{userId}
Body: { "role": "admin" }

# Remove a member (owner or admin, or a member removing themselves; never the owner)
DELETE /organizations/{id}/members/{userId}

# Transfer ownership (owner only; previous owner becomes admin)
POST /organizations/{id}/transfer-ownership
Body: { "email": "new-owner@example.com" }

# Dissolve (owner only; runs in the background)
DELETE /organizations/{id}
```

While an organization is dissolving, member and settings changes return `409`.

## 12. Subscription and Upgrades

```
# Current plan (users with no subscription get plan "free", status "active")
GET /billing/subscription

# Free -> paid: send the user to Stripe Checkout
POST /billing/checkout
Body: { "plan": "starter" }
Response: { "sessionUrl": "https://checkout.stripe.com/..." }

# Paid -> higher paid plan: preview, then upgrade
POST /billing/upgrade/preview
Body: { "plan": "team" }
Response: { "immediateAmountCents": 5000, "currency": "usd", "targetPlan": "team",
            "currentPeriodEnd": "..." }

POST /billing/upgrade
Body: { "plan": "team" }
Response: { "plan": "team", "status": "active", "currentPeriodEnd": "...", "cancelAtPeriodEnd": false }

# Payment methods, invoices, cancellation
POST /billing/portal
Response: { "portalUrl": "https://billing.stripe.com/..." }
```

The upgrade charge is the flat difference between the two plan prices, charged immediately. Upgrade and preview return `404` without an active paid subscription and `400` if the target plan is not higher than the current one. In an organization only the owner can use checkout, portal, preview, and upgrade (`403` for other members). Always confirm with the user before calling `upgrade`, since it charges their card.

## Plan Limits

| Resource | Free | Starter | Team | Business | Enterprise |
|----------|------|---------|------|----------|------------|
| Domains | 3 | 10 | 25 | 75 | unlimited |
| API keys | 2 | 5 | 10 | 25 | unlimited |
| Certificates created per calendar month (UTC) | 5 | 50 | 250 | 1000 | unlimited |
| Issued certificates | 10 | 75 | 375 | 1500 | unlimited |
| Concurrent pending/issuing/renewing | 2 | 5 | 25 | 100 | unlimited |
| Auto-renewal window (days before expiry) | 5 | 30 | 30 | 30 | 30 |
| Monitored endpoints | 3 | 10 | 50 | 200 | unlimited |
| Hosted regions (total across endpoints) | 0 | 2 | 5 | 15 | unlimited |
| Endpoints with hosted monitoring | 0 | 5 | 25 | 100 | unlimited |
| Scan result retention (days) | 5 | 30 | 90 | 90 | 90 |

Limits are counted across all members of an organization.

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
- `402`: plan limit reached (domains, API keys, certificate limits) or a feature that needs a higher plan (organizations). `message` names the limit, for example "Monthly certificate limit reached". Tell the user; retrying will not help until they upgrade or free up capacity.
- `403`: not allowed. Endpoint and hosted-region plan limits ("Endpoint limit reached", "Hosted monitoring is not available on your plan"), org role checks, billing outside the org owner, or admin-only routes.
- `404`: the resource does not exist or the caller cannot see it.
- `409`: conflict. Duplicate certificate request still in progress, already in an organization, or the organization is dissolving.
- `429`: rate limited. Wait for the number of seconds in the `Retry-After` response header before retrying. Also returned after too many invalid API key attempts from one IP.
- `500`: server or CA error. For revocation, the certificate stays `issued`; retry later.
- `503`: dependency unavailable (readiness check, public scan).

Plan limit responses currently contain only the standard fields above. Do not rely on extra fields such as `code`, `limit`, or `current`; use the status code and `message`.

## Rate Limiting

Limits depend on the plan and the route category. Each tool in `tool-definitions.json` has a `rate_limit_category`.

| Plan | public | read | write | expensive |
|------|--------|------|-------|-----------|
| free | 30/min | 60/min | 20/min | 5/hour |
| starter | 60/min | 120/min | 40/min | 10/hour |
| team | 60/min | 300/min | 60/min | 30/hour |
| business | 120/min | 600/min | 120/min | 60/hour |
| enterprise | 120/min | 1000/min | 200/min | 100/hour |

How it is applied:

- Each route has its own counter. Five certificate requests per hour on free does not use up the five renewals or five domain verifications.
- Requests with a JWT are counted per user at the user's plan.
- Requests with a `kk_` API key are counted per client IP at the free-plan limits, whatever the user's plan. Several keys behind the same IP share a counter.
- Unauthenticated requests are counted per client IP at the free-plan limits.
- Windows are fixed. Exceeding a limit blocks that route for one full window (one minute, or one hour for `expensive`).
- Successful responses include `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset`. A `429` includes `Retry-After` in seconds.

Polling guidance: poll `GET /certs/tls/{id}` every 15-30 seconds (a `read` route). Never poll `verify`, `renew`, `retry`, `revoke`, or `POST /certs/tls`; they are `expensive`.
