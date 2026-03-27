# KrakenKey API Skill for AI Agents

Structured tool definitions for AI agents to interact with the KrakenKey REST API.

## Files

- `tool-definitions.json` -- Machine-readable tool definitions with parameters, auth requirements, and response schemas. Compatible with function-calling / tool-use formats used by LLM frameworks.
- `workflows.md` -- Common multi-step workflows (issue a cert, verify a domain, set up monitoring, etc.) that agents can follow.

## Authentication

All protected endpoints require:

```
Authorization: Bearer <token>
```

Three token types:
- **User API keys** (`kk_` prefix) -- for user-facing operations and connected probes
- **JWT tokens** -- obtained through OAuth flow, used by the web frontend
- **Service keys** (`kk_svc_` prefix) -- for hosted probe infrastructure (internal use)

Probe endpoints (`/probes/*`) accept either user API keys or service keys (dual auth). All other authenticated endpoints accept JWT or user API keys.

## Coverage

The tool definitions cover:

| Area | Tools |
|------|-------|
| Health & status | `get_api_status`, `health_check` |
| Auth & API keys | `get_profile`, `update_profile`, `list_api_keys`, `create_api_key`, `delete_api_key` |
| Domains | `list_domains`, `register_domain`, `get_domain`, `verify_domain`, `delete_domain` |
| Certificates | `list_certificates`, `submit_csr`, `get_certificate`, `get_certificate_details`, `update_certificate`, `renew_certificate`, `retry_certificate`, `revoke_certificate`, `delete_certificate` |
| Endpoints | `list_endpoints`, `create_endpoint`, `get_endpoint`, `update_endpoint`, `delete_endpoint`, `add_hosted_region`, `remove_hosted_region`, `get_endpoint_results`, `get_endpoint_latest_results` |
| Probes | `register_probe`, `submit_probe_report`, `get_probe_config` |
| Organizations | `create_organization`, `get_organization`, `invite_member`, `update_member_role`, `remove_member` |
| Billing | `get_subscription`, `preview_upgrade`, `upgrade_plan` |
| Feedback | `submit_feedback` |

## Quick Reference

The live OpenAPI spec is always available at `GET /swagger-json` on any running KrakenKey API instance. These tool definitions are a simplified, agent-friendly projection of that spec.
