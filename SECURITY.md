# Security Policy

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability in KrakenKey, please report it responsibly by emailing:

**security@krakenkey.io**

Include:

1. Description of the vulnerability
2. Steps to reproduce
3. Potential impact
4. Suggested fix (if any)

## Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 5 business days
- **Fix timeline**: Depends on severity, typically within 30 days

## Scope

This policy applies to:

- The KrakenKey application (backend API and frontend dashboard)
- The managed service at krakenkey.io
- The KrakenKey REST API

Out of scope:

- Third-party services (Let's Encrypt, DNS providers)
- Social engineering attacks
- Denial of service attacks

## Supported Versions

| Version | Supported |
| ------- | --------- |
| Latest  | Yes       |

## Security Measures

KrakenKey implements the following security measures:

- **Pre-commit secrets scanning** -- gitleaks prevents accidental credential commits
- **CSR signature verification** -- all submitted CSRs are cryptographically validated
- **Client-side key generation** -- private keys are generated in the browser via WebCrypto and never transmitted to the server
- **API key hashing** -- API keys are hashed before storage
- **OIDC authentication** -- user authentication via OpenID Connect
- **Tier-aware rate limiting** -- configurable throttling on all endpoints

## Acknowledgments

We appreciate responsible disclosure and will acknowledge security researchers who report valid vulnerabilities (with your permission).
