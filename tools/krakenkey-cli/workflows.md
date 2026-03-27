# KrakenKey CLI Workflows

Common multi-step workflows using the `krakenkey` CLI.

## 1. Initial Setup

```bash
# Install (from source)
cd cli && go build -o krakenkey ./cmd/krakenkey

# Authenticate
krakenkey auth login --api-key kk_abc123...

# Verify connection
krakenkey auth status
```

## 2. Domain Setup and Certificate Issuance

```bash
# Register a domain
krakenkey domain add example.com
# Output includes:
#   Verification code: krakenkey-site-verification=abc123
#   CNAME target: example-com.acme.krakenkey.io

# (User sets up DNS records at their registrar)

# Verify domain ownership
krakenkey domain verify <domain-id>

# Issue a certificate (generates key + CSR locally, submits, waits for issuance)
krakenkey cert issue --domain example.com --wait
# Output: private key saved to ./example.com.key, cert saved to ./example.com.crt

# Or submit an existing CSR
krakenkey cert submit --csr ./my-request.csr --wait --out ./my-cert.crt
```

## 3. Certificate Management

```bash
# List all certificates
krakenkey cert list

# Filter by status
krakenkey cert list --status issued

# Check certificate details
krakenkey cert show 42

# Download just the PEM
krakenkey cert download 42 --out ./example.crt

# Renew (and wait for completion)
krakenkey cert renew 42 --wait

# Toggle auto-renewal
krakenkey cert update 42 --auto-renew=true

# Revoke
krakenkey cert revoke 42 --reason 4

# Delete a revoked/failed cert
krakenkey cert delete 42
```

## 4. Endpoint Monitoring Setup

```bash
# Add endpoints to monitor
krakenkey endpoint add example.com --label "Production"
krakenkey endpoint add api.example.com --port 8443 --label "API Gateway"

# List all monitored endpoints
krakenkey endpoint list

# Add hosted probe regions (Team tier+)
krakenkey endpoint region add <endpoint-id> us-east-1
krakenkey endpoint region add <endpoint-id> eu-west-1

# Check endpoint details
krakenkey endpoint show <endpoint-id>

# Pause monitoring temporarily
krakenkey endpoint disable <endpoint-id>

# Resume monitoring
krakenkey endpoint enable <endpoint-id>

# Remove a hosted region
krakenkey endpoint region remove <endpoint-id> eu-west-1

# Delete an endpoint
krakenkey endpoint delete <endpoint-id>
```

## 5. API Key Management

```bash
# List existing keys
krakenkey auth keys list

# Create a new key for CI
krakenkey auth keys create --name ci-deploy --expires-at 2027-01-01T00:00:00Z
# IMPORTANT: Copy the kk_... value immediately -- shown only once

# Delete a key
krakenkey auth keys delete <key-id>
```

## 6. Account and Billing

```bash
# View profile
krakenkey account show

# Check subscription plan
krakenkey account plan
```

## 7. JSON Output for Scripting

All commands support `--output json` for machine-readable output:

```bash
# Get endpoints as JSON, pipe to jq
krakenkey --output json endpoint list | jq '.[].host'

# Get cert details as JSON
krakenkey --output json cert show 42 | jq '.status'

# List domains and filter verified ones
krakenkey --output json domain list | jq '[.[] | select(.isVerified)]'
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Authentication failure |
| 3 | Resource not found |
| 4 | Rate limited |
| 5 | Configuration error |
