# KrakenKey Cert Action

[![Test](https://github.com/krakenkey/cert-action/actions/workflows/test.yaml/badge.svg)](https://github.com/krakenkey/cert-action/actions/workflows/test.yaml)
[![GitHub Release](https://img.shields.io/github/v/release/krakenkey/cert-action)](https://github.com/krakenkey/cert-action/releases)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)

Issue, renew, or download TLS certificates from [KrakenKey](https://krakenkey.io) directly in your GitHub Actions workflows. As certificate lifetimes shrink to 200 days (March 2026), 100 days (March 2027), and 47 days (March 2029) under CA/B Forum SC-081, automated certificate management in CI/CD becomes essential. This action wraps the `krakenkey-cli` binary to make TLS certificate issuance a first-class CI/CD primitive.

## Quick Start

```yaml
- name: Issue TLS certificate
  id: cert
  uses: krakenkey/cert-action@v1
  with:
    api-key: ${{ secrets.KRAKENKEY_API_KEY }}
    domain: api.example.com
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `api-key` | KrakenKey API key (starts with `kk_`). Use `${{ secrets.KRAKENKEY_API_KEY }}` | Yes | — |
| `api-url` | KrakenKey API base URL | No | `https://api.krakenkey.io` |
| `command` | Action to perform: `issue`, `renew`, or `download` | No | `issue` |
| `domain` | Primary domain (CN) for the certificate | `issue` only | — |
| `san` | Additional Subject Alternative Names (comma-separated) | No | `""` |
| `key-type` | Key type: `rsa-2048`, `rsa-4096`, `ecdsa-p256`, `ecdsa-p384` | No | `ecdsa-p256` |
| `subject-org` | Organization (O) subject field | No | `""` |
| `subject-ou` | Organizational Unit (OU) subject field | No | `""` |
| `subject-country` | Country (C, 2-letter ISO) subject field | No | `""` |
| `auto-renew` | Enable server-side auto-renewal | No | `true` |
| `cert-id` | Certificate ID for `renew` or `download` commands | `renew`/`download` | — |
| `wait` | Wait for issuance/renewal to complete | No | `true` |
| `poll-interval` | Poll interval when waiting (Go duration, e.g., `15s`) | No | `15s` |
| `poll-timeout` | Maximum time to wait (Go duration, e.g., `10m`) | No | `10m` |
| `cert-path` | Path to save the certificate PEM | No | `./cert.pem` |
| `key-path` | Path to save the private key PEM (issue only) | No | `./key.pem` |
| `csr-path` | Path to save the CSR PEM (issue only) | No | `./csr.pem` |
| `cli-version` | `krakenkey-cli` version to use (e.g., `v0.1.0`, or `latest`) | No | `latest` |

## Outputs

| Output | Description |
|--------|-------------|
| `cert-id` | Certificate ID |
| `status` | Certificate status (`pending`, `issuing`, `issued`, `failed`) |
| `domain` | Primary domain (CN) |
| `sans` | Subject Alternative Names (comma-separated) |
| `issuer` | Certificate issuer (e.g., `CN=R11,O=Let's Encrypt,C=US`) |
| `serial-number` | Certificate serial number |
| `expires` | Expiration date (ISO 8601) |
| `fingerprint` | SHA-256 fingerprint |
| `key-type` | Key type used (e.g., `ECDSA`) |
| `key-size` | Key size (e.g., `256`, `2048`) |
| `cert-path` | Absolute path to the saved certificate PEM |
| `key-path` | Absolute path to the saved private key PEM (issue only) |
| `csr-path` | Absolute path to the saved CSR PEM (issue only) |

## Commands

### `issue` (default)

Generates a CSR locally, submits it to the KrakenKey API, waits for issuance (~4 minutes), and saves the certificate + private key to the runner filesystem.

**Required inputs:** `api-key`, `domain`

### `renew`

Triggers renewal of an existing certificate by ID, waits for completion, and downloads the new certificate.

**Required inputs:** `api-key`, `cert-id`

### `download`

Downloads an already-issued certificate by ID. No issuance, no waiting.

**Required inputs:** `api-key`, `cert-id`

## Usage Examples

<details>
<summary>Basic: Issue a certificate on deploy</summary>

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Issue TLS certificate
        id: cert
        uses: krakenkey/cert-action@v1
        with:
          api-key: ${{ secrets.KRAKENKEY_API_KEY }}
          domain: api.example.com
          key-type: ecdsa-p256

      - name: Deploy with certificate
        run: |
          scp ${{ steps.cert.outputs.cert-path }} server:/etc/ssl/certs/
          scp ${{ steps.cert.outputs.key-path }} server:/etc/ssl/private/
          ssh server 'systemctl reload nginx'
```

</details>

<details>
<summary>Multi-domain certificate with SANs</summary>

```yaml
      - name: Issue multi-domain cert
        id: cert
        uses: krakenkey/cert-action@v1
        with:
          api-key: ${{ secrets.KRAKENKEY_API_KEY }}
          domain: example.com
          san: "www.example.com,api.example.com,cdn.example.com"
          key-type: rsa-4096
          subject-org: "Example Inc"
          subject-country: "US"
```

</details>

<details>
<summary>Renew an existing certificate</summary>

```yaml
      - name: Renew certificate
        id: cert
        uses: krakenkey/cert-action@v1
        with:
          api-key: ${{ secrets.KRAKENKEY_API_KEY }}
          command: renew
          cert-id: '42'
          cert-path: ./renewed-cert.pem
```

</details>

<details>
<summary>Download only (certificate already issued)</summary>

```yaml
      - name: Download certificate
        id: cert
        uses: krakenkey/cert-action@v1
        with:
          api-key: ${{ secrets.KRAKENKEY_API_KEY }}
          command: download
          cert-id: '42'
          cert-path: ./cert.pem
```

</details>

<details>
<summary>Scheduled renewal in CI</summary>

```yaml
name: Certificate Renewal
on:
  schedule:
    - cron: '0 6 * * 1'  # Every Monday at 6 AM

jobs:
  renew:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        cert:
          - { id: 42, name: "api.example.com" }
          - { id: 43, name: "app.example.com" }
    steps:
      - name: Renew ${{ matrix.cert.name }}
        id: cert
        uses: krakenkey/cert-action@v1
        with:
          api-key: ${{ secrets.KRAKENKEY_API_KEY }}
          command: renew
          cert-id: ${{ matrix.cert.id }}

      - name: Deploy renewed cert
        if: steps.cert.outputs.status == 'issued'
        run: |
          echo "Renewed ${{ matrix.cert.name }} — expires ${{ steps.cert.outputs.expires }}"
```

</details>

<details>
<summary>Using outputs in downstream steps</summary>

```yaml
      - name: Issue cert
        id: cert
        uses: krakenkey/cert-action@v1
        with:
          api-key: ${{ secrets.KRAKENKEY_API_KEY }}
          domain: api.example.com

      - name: Verify and log
        run: |
          echo "Certificate #${{ steps.cert.outputs.cert-id }}"
          echo "Domain: ${{ steps.cert.outputs.domain }}"
          echo "Issuer: ${{ steps.cert.outputs.issuer }}"
          echo "Expires: ${{ steps.cert.outputs.expires }}"
          echo "Fingerprint: ${{ steps.cert.outputs.fingerprint }}"
          openssl x509 -in ${{ steps.cert.outputs.cert-path }} -noout -text
```

</details>

<details>
<summary>Non-waiting mode (fire and forget)</summary>

```yaml
      - name: Request cert (don't wait)
        id: cert
        uses: krakenkey/cert-action@v1
        with:
          api-key: ${{ secrets.KRAKENKEY_API_KEY }}
          domain: api.example.com
          wait: 'false'

      - name: Continue deployment
        run: echo "Certificate #${{ steps.cert.outputs.cert-id }} requested (status: ${{ steps.cert.outputs.status }})"
```

</details>

## Security

- **API key masking** — The API key is masked with `::add-mask::` as the very first operation, ensuring it is redacted from all log output.
- **API key not in process list** — The CLI is invoked with the `KK_API_KEY` environment variable instead of a `--api-key` flag, so the key does not appear in `ps` output.
- **Private key permissions** — Private key files are written with `chmod 0600`. The action does NOT upload artifacts — deploying or storing the private key securely is the user's responsibility.
- **Checksum verification** — The CLI binary is verified against goreleaser SHA-256 checksums before execution, protecting against CDN/mirror compromise.
- **Pinned CLI version** — Use the `cli-version` input to pin a specific CLI release and avoid supply chain drift.

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Authentication failed` | Invalid or missing API key | Verify `KRAKENKEY_API_KEY` secret is set in repo settings |
| `Missing required input: domain` | `domain` not provided for `issue` command | Add `domain` input |
| `Missing required input: cert-id` | `cert-id` not provided for `renew`/`download` | Add `cert-id` input |
| `Certificate or resource not found` | Invalid `cert-id` | Check certificate ID in KrakenKey dashboard |
| `Rate limited` | Too many API requests | Wait and retry, or upgrade your KrakenKey plan |
| `Invalid api-key format` | API key doesn't start with `kk_` | Use the API key from your KrakenKey dashboard |
| Timeout during issuance | DNS-01 challenge took too long | Check domain DNS configuration; increase `poll-timeout` |

## Prerequisites

1. A [KrakenKey](https://krakenkey.io) account
2. A verified domain in your KrakenKey dashboard
3. An API key (starts with `kk_`) stored as a GitHub Actions secret

## License

[AGPL-3.0](LICENSE)
