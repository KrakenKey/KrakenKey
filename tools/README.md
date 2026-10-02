# KrakenKey AI Agent Skills

Structured tool and workflow definitions for AI agents to interact with KrakenKey.

## Available Skills

### [krakenkey-api](krakenkey-api/)

REST API tool definitions, one per public API route: certificate lifecycle (including the full chain), domain management, endpoint monitoring, connected probes, public scan, organizations, users, and billing. Includes multi-step workflow guides, error handling, and rate limit rules.

Use this when an agent needs to make HTTP requests to the KrakenKey API.

### [krakenkey-cli](krakenkey-cli/)

CLI tool definitions for the `krakenkey` command-line interface (v0.4.0). Covers every command: auth, domain, cert, endpoint, account, and version. Includes workflow guides, exit codes, and scripting patterns.

Use this when an agent needs to run `krakenkey` CLI commands in a terminal or CI job. Always pass `--output json` (before the command) and parse stdout.

## Structure

Each skill directory contains:

- `README.md` -- Overview and authentication info
- `tool-definitions.json` -- Machine-readable tool definitions (parameters, types, examples)
- `workflows.md` -- Multi-step workflow guides for common tasks

## Before you start

- Domains need two DNS records before issuance: the TXT record for ownership and a CNAME from `_acme-challenge.<domain>` to KrakenKey's ACME zone. Issuance checks the CNAME first and fails without retrying if it is missing.
- Retrying a certificate request with the same CSR within 15 minutes is safe; it returns the original certificate.
- Stop on the first `401`. Repeated failed API key attempts lock the client IP out of API key auth for 15 minutes.

See [AGENTS.md](../AGENTS.md) for the full API reference, rate limits, and plan limits.
