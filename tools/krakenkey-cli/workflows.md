# KrakenKey CLI Workflows

Common multi-step workflows using the `krakenkey` CLI (v0.6.0). See [README.md](README.md) for global flags, output formats, and exit codes.

Global flags (`--output`, `--api-key`, `--api-url`, `--no-color`) go **before** the command.

## 1. Install and Authenticate

```bash
# Install: download a release archive from https://github.com/KrakenKey/cli/releases,
# or build it yourself
go install github.com/krakenkey/cli/cmd/krakenkey@latest
# or, from a clone of the cli repo
go build -o krakenkey ./cmd/krakenkey

krakenkey version

# Option A: browser approval (preferred for agents working with a person).
# Prints a link and code to stderr; the user approves in the dashboard and the
# new key is saved to ~/.config/krakenkey/config.yaml. Waits up to 10 minutes,
# so run it in the background and send the user the link.
krakenkey auth login --web --no-browser > /tmp/krakenkey-login.log 2>&1 &
sleep 3; cat /tmp/krakenkey-login.log

# Option B: env var (preferred for CI; nothing is written to disk)
export KK_API_KEY=kk_abc123...

# Option C: save an existing key to the config file
# (the key is checked against the API before it is saved)
krakenkey auth login --api-key kk_abc123...

# Confirm the key works
krakenkey auth status
```

If any command fails with `config file has insecure permissions` (exit 5), the config file is readable or writable by group or other users. Fix it and rerun:

```bash
chmod 600 ~/.config/krakenkey/config.yaml
```

## 2. JSON Output for Scripting

Use `--output json` (or `export KK_OUTPUT=json`) whenever the output will be parsed. Text mode is for humans only.

```bash
# Endpoint hosts
krakenkey --output json endpoint list | jq -r '.[].host'

# Status of one certificate
krakenkey --output json cert show 42 | jq -r '.status'

# Verified domains only
krakenkey --output json domain list | jq '[.[] | select(.isVerified)]'
```

Errors are written to stderr as `{"error":"..."}`. Delete and remove commands, `auth login`, and `auth logout` print nothing on success, so check the exit code.

## 3. Domain Setup (TXT + CNAME)

Each domain needs two DNS records before a certificate can be issued:

1. A **TXT** record at the domain itself, proving ownership.
2. A **CNAME** from `_acme-challenge.<domain>` to KrakenKey's ACME zone, so KrakenKey can answer DNS-01 challenges. The target is the domain with dots replaced by dashes, under `acme.krakenkey.io`.

```bash
# Register the domain; JSON includes the ID and both records
krakenkey --output json domain add example.com | jq -r '.id, (.dnsRecords[] | "\(.type) \(.name) \(.value)")'
# <domain-id>
# TXT example.com krakenkey-site-verification=<hex>
# CNAME _acme-challenge.example.com example-com.acme.krakenkey.io
```

Create these records at the DNS provider:

```text
example.com.                  TXT    "krakenkey-site-verification=<hex>"
_acme-challenge.example.com.  CNAME  example-com.acme.krakenkey.io.
```

Every name in the certificate needs its own `_acme-challenge` CNAME. For example, a cert that also covers `www.example.com` needs `_acme-challenge.www.example.com. CNAME www-example-com.acme.krakenkey.io.` A wildcard (`*.example.com`) uses the same `_acme-challenge.example.com` record as its base domain.

`domain add` prints the TXT and the CNAME for the domain itself. Check every name the certificate will cover before continuing; `--wait` re-checks every 30 seconds until all records are in place:

```bash
krakenkey --output json domain check example.com www.example.com --resolver 1.1.1.1 --wait
```

Each record comes back as `ok`, `missing`, `wrong` (with the current target in `found`), `conflict` (TXT records where the CNAME must go), `unregistered` or `skipped` (no API key, so the TXT isn't checked). The command exits 1 until everything is `ok`.

Then verify ownership:

```bash
krakenkey domain verify <domain-id>
```

`domain verify` checks the TXT record only. It exits 1 if the record is not found yet; wait for DNS propagation and run it again. The CNAME is checked later, when a certificate is issued (see section 5).

## 4. Issue a Certificate

The CLI generates the private key and CSR locally. The key never leaves the machine. Issuance usually takes a few minutes.

### Issue and wait

```bash
krakenkey cert issue --domain example.com --san www.example.com --wait
```

This writes, in the current directory:

| File | Contents |
|------|----------|
| `example.com.key` | Private key (mode 0600), written before submission |
| `example.com.csr` | CSR, written before submission |
| `example.com.crt` | Leaf certificate, written after issuance |
| `example.com.chain.crt` | Intermediate chain, written after issuance |
| `example.com.fullchain.crt` | Leaf + intermediates, written after issuance |

Most web servers (nginx, Caddy, HAProxy) want the full chain. Override paths as needed:

```bash
krakenkey cert issue --domain example.com --wait \
  --key-out /etc/ssl/private/example.com.key \
  --fullchain-out /etc/ssl/certs/example.com.fullchain.crt
```

`--wait` polls every 15s for up to 10m (`--poll-interval`, `--poll-timeout`). If it times out, the CLI exits 1 but does not cancel anything; keep polling with `cert show` and fetch the files with `cert download`.

### Issue, poll, download (scripted)

Without `--wait`, only the key and CSR are written. Poll the status and download when it reaches `issued`:

```bash
export KK_OUTPUT=json

CERT_ID=$(krakenkey cert issue --domain example.com | jq -r '.id')

while :; do
  STATUS=$(krakenkey cert show "$CERT_ID" | jq -r '.status')
  case "$STATUS" in
    issued) break ;;
    failed|revoked) echo "certificate $CERT_ID is $STATUS" >&2; exit 1 ;;
  esac
  sleep 15
done

krakenkey cert download "$CERT_ID" --format fullchain --out ./example.com.fullchain.crt
krakenkey cert download "$CERT_ID" --out ./example.com.crt
```

### Submit an existing CSR

```bash
krakenkey cert submit --csr ./my-request.csr --wait \
  --out ./my-cert.crt --fullchain-out ./my-cert.fullchain.crt
```

Default output names use the CSR's CN (`<cn>.crt`, `<cn>.chain.crt`, `<cn>.fullchain.crt`).

## 5. When Issuance Fails

Before contacting the CA, KrakenKey checks that `_acme-challenge.<name>` is a CNAME to the expected target for every name in the CSR. If the CNAME is missing or points somewhere else, the certificate fails right away, with no retries, and the failure notification email names the exact record to create or fix:

```text
ACME challenge delegation missing: no CNAME found at _acme-challenge.example.com. Create a CNAME record from _acme-challenge.example.com to example-com.acme.krakenkey.io, then request the certificate again (if you just created it, allow a few minutes for DNS to update).
```

A CNAME that points to the wrong target fails with `ACME challenge delegation mismatch: ... points to ..., expected ...` instead.

The CLI shows the same reason: `cert issue --wait` exits 1 with `certificate issuance failed for example.com: <reason>`, and `cert show` prints a `Reason:` line (`failureReason` in JSON).

To recover:

```bash
# 1. Fix the CNAME and confirm it is in place
krakenkey domain check example.com --resolver 1.1.1.1

# 2. Retry the same certificate (same CSR and key) and wait
krakenkey cert retry <cert-id> --wait

# 3. Write the files (retry does not write them)
krakenkey cert download <cert-id> --format fullchain --out ./example.com.fullchain.crt
krakenkey cert download <cert-id> --out ./example.com.crt
```

The private key from the original `cert issue` stays valid, because retry reuses the same CSR.

## 6. Renewal

New certificates have auto-renewal on by default. To renew by hand:

```bash
krakenkey cert renew 42 --wait

# renew does not write files; fetch the new cert
krakenkey cert download 42 --format fullchain --out ./example.com.fullchain.crt
```

Renewal reuses the stored CSR, so the existing private key keeps working.

## 7. Certificate Management

```bash
# List all certificates, or filter by status
krakenkey cert list
krakenkey cert list --status issued

# Details, including the intermediate chain for issued certs (text mode)
krakenkey cert show 42

# Download a specific format: cert (default), chain, or fullchain
krakenkey cert download 42 --format chain --out ./example.com.chain.crt

# Turn auto-renewal off or on (use the = form)
krakenkey cert update 42 --auto-renew=false
krakenkey cert update 42 --auto-renew=true

# Revoke (optional RFC 5280 reason code 0-10)
krakenkey cert revoke 42 --reason 4

# Delete a failed or revoked certificate
krakenkey cert delete 42
```

## 8. Endpoint Monitoring

```bash
# Add endpoints
krakenkey endpoint add example.com --label "Production"
krakenkey endpoint add api.example.com --port 8443 --sni api.example.com --label "API Gateway"

# List and inspect
krakenkey endpoint list
krakenkey endpoint show <endpoint-id>

# Connected probes (your own probe running in connected mode)
krakenkey endpoint probes
krakenkey endpoint add internal.example.com --probe <probe-id>
krakenkey endpoint probe add <endpoint-id> <probe-id>
krakenkey endpoint probe remove <endpoint-id> <probe-id>

# Hosted probe regions (Starter tier and up)
krakenkey endpoint region add <endpoint-id> us-east-1
krakenkey endpoint region remove <endpoint-id> us-east-1

# Request an on-demand scan
krakenkey endpoint scan <endpoint-id>

# Pause and resume monitoring
krakenkey endpoint disable <endpoint-id>
krakenkey endpoint enable <endpoint-id>

# Delete
krakenkey endpoint delete <endpoint-id>
```

The CLI does not display scan results. Read them in the dashboard or through the API (`GET /endpoints/:id/results`).

## 9. API Key Management

```bash
krakenkey auth keys list
```

API keys can't create or delete keys: the API answers `auth keys create` and `auth keys delete` with a 403 unless the caller has a dashboard session, and the CLI only ever has a key. To get a key for another machine or a CI job, ask the user to create it under **API Keys** in the dashboard (app.krakenkey.io/dashboard/api-keys), or run `krakenkey auth login --web` on that machine and have the user approve it. Revoking a key is also done in the dashboard.

## 10. Account and Billing

```bash
# Profile and resource counts
krakenkey account show

# Subscription plan, status, and period end
krakenkey account plan
```
