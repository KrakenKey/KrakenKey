# KrakenKey API Workflows

Common multi-step workflows for AI agents interacting with the KrakenKey API.

## 1. Issue a Certificate (End-to-End)

Prerequisites: authenticated user, domain already verified.

```
Step 1: Generate a CSR locally (openssl or equivalent)
  $ openssl req -new -newkey rsa:2048 -nodes \
      -keyout private.key -out request.csr \
      -subj "/CN=example.com" \
      -addext "subjectAltName=DNS:example.com,DNS:www.example.com"

Step 2: Submit CSR
  POST /certs/tls
  Body: { "csrPem": "<PEM contents of request.csr>" }
  Response: { "id": 42, "status": "pending" }

Step 3: Poll for completion (every 10-30 seconds, up to 10 minutes)
  GET /certs/tls/42
  Wait until status is "issued" or "failed"

Step 4: Retrieve the certificate
  GET /certs/tls/42
  The crtPem field contains the issued certificate in PEM format

Step 5 (optional): Get parsed certificate details
  GET /certs/tls/42/details
  Returns: serialNumber, issuer, subject, validFrom, validTo, fingerprint
```

## 2. Register and Verify a Domain

```
Step 1: Register the domain
  POST /domains
  Body: { "hostname": "example.com" }
  Response: { "id": "uuid", "hostname": "example.com", "verificationCode": "krakenkey-site-verification=abc123", "isVerified": false }

Step 2: User sets up DNS records at their registrar
  TXT record at @:                krakenkey-site-verification=abc123
  CNAME at _acme-challenge:       example-com.acme.krakenkey.io

Step 3: Wait for DNS propagation (1-5 minutes typically)

Step 4: Trigger verification
  POST /domains/{id}/verify
  Response: updated domain object with isVerified: true (or error if DNS not found)
```

Note: step 2 requires the user to act outside the API. The agent should instruct the user on what DNS records to create and wait for confirmation before triggering verification.

## 3. Create an API Key

Requires an active JWT session (obtained via OAuth login).

```
Step 1: Create the key
  POST /auth/api-keys
  Body: { "name": "my-ci-key", "expiresAt": "2027-01-01T00:00:00Z" }
  Response: { "apiKey": "kk_abc123...", "id": "uuid", "name": "my-ci-key" }

IMPORTANT: The apiKey value is returned only once. Store it immediately.

Step 2: Use the key for subsequent requests
  Authorization: Bearer kk_abc123...
```

## 4. Renew a Certificate

```
Step 1: Check certificate status
  GET /certs/tls/{id}
  Verify status is "issued" and check expiresAt

Step 2: Trigger renewal
  POST /certs/tls/{id}/renew
  Response: { "id": 42, "status": "renewing" }

Step 3: Poll for completion
  GET /certs/tls/{id}
  Wait until status returns to "issued"
```

## 5. Revoke a Certificate

```
Step 1: Revoke
  POST /certs/tls/{id}/revoke
  Body: { "reason": 0 }   (0=unspecified, 1=keyCompromise, 4=superseded, 5=cessationOfOperation)
  Response: { "id": 42, "status": "revoking" }

Step 2: Poll until status is "revoked"
  GET /certs/tls/{id}

Step 3 (optional): Delete the revoked record
  DELETE /certs/tls/{id}
```

## 6. Manage Organization Members

```
# Create an org
POST /organizations
Body: { "name": "My Team" }

# Invite a member
POST /organizations/{id}/members
Body: { "email": "colleague@example.com", "role": "member" }

# Change role
PATCH /organizations/{id}/members/{userId}
Body: { "role": "admin" }

# Remove member
DELETE /organizations/{id}/members/{userId}

# Transfer ownership
POST /organizations/{id}/transfer-ownership
Body: { "email": "new-owner@example.com" }
```

## 7. Check Subscription and Upgrade

```
# Current plan
GET /billing/subscription
Response: { "plan": "free", "status": "active", ... }

# Preview upgrade cost
POST /billing/upgrade/preview
Body: { "plan": "starter" }
Response: { "immediateAmountCents": 500, "currency": "usd", ... }

# Upgrade
POST /billing/upgrade
Body: { "plan": "starter" }
```

## 8. Set Up Endpoint Monitoring

```
Step 1: Create an endpoint
  POST /endpoints
  Body: { "host": "example.com", "port": 443, "label": "Production API" }
  Response: { "id": "uuid", "host": "example.com", "port": 443, "isActive": true }

Step 2 (optional): Add hosted probe regions (Team tier+)
  POST /endpoints/{id}/regions
  Body: { "region": "us-east-1" }
  Repeat for additional regions (e.g., eu-west-1, ap-southeast-1)

Step 3: Set up a connected probe
  Install the krakenkey-probe binary
  Configure with user API key:
    KK_PROBE_API_KEY=kk_...
    KK_PROBE_MODE=connected
  The probe will fetch its endpoint list from GET /probes/{id}/config

Step 4: View scan results
  GET /endpoints/{id}/results/latest
  Returns the most recent scan per probe (connection status, cert expiry, TLS version)

  GET /endpoints/{id}/results?page=1&limit=20
  Returns paginated historical results
```

## 9. Monitor Endpoint Health

```
# List all endpoints with status
GET /endpoints
Returns all endpoints with hostedRegions included

# Check latest results (aggregated across probes)
GET /endpoints/{id}/results/latest
Each result includes: connectionSuccess, latencyMs, certDaysUntilExpiry, probeMode, probeRegion

# Disable/enable monitoring
PATCH /endpoints/{id}
Body: { "isActive": false }

# Remove hosted region
DELETE /endpoints/{id}/regions/us-east-1
```

## 10. Connected Probe Setup (Self-Hosted)

```
# Probe authenticates with a user API key (not service key)
# 1. User creates an API key
POST /auth/api-keys
Body: { "name": "my-probe" }
Response: { "apiKey": "kk_abc123..." }

# 2. Configure the probe
KK_PROBE_API_URL=https://api.krakenkey.io
KK_PROBE_API_KEY=kk_abc123...
KK_PROBE_MODE=connected

# 3. Probe registers itself on startup
POST /probes/register (with Bearer kk_abc123...)
Body: { "probeId": "auto-uuid", "name": "my-probe", "version": "0.1.0", "mode": "connected", "os": "linux", "arch": "amd64" }

# 4. Probe fetches its endpoint list
GET /probes/{probeId}/config
Response: { "endpoints": [{ "host": "example.com", "port": 443 }], "interval": "60m" }

# 5. After scanning, probe reports results
POST /probes/report
Body: { "probeId": "...", "mode": "connected", "timestamp": "...", "results": [...] }
```

## Error Handling

All errors return:

```json
{
  "statusCode": 400,
  "message": "description of what went wrong",
  "error": "Bad Request",
  "timestamp": "2026-03-24T10:30:00.000Z",
  "path": "/certs/tls"
}
```

Key status codes to handle:
- `401` -- re-authenticate (API key may be expired or invalid)
- `404` -- resource doesn't exist
- `429` -- rate limited, back off and retry after delay
- `400` -- fix the request (validation error, wrong state for operation)
