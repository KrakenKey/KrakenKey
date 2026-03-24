# KrakenKey API Tools for AI Agents

Structured tool definitions for AI agents to interact with the KrakenKey REST API.

## Files

- `tool-definitions.json` -- Machine-readable tool definitions with parameters, auth requirements, and response schemas. Compatible with function-calling / tool-use formats used by LLM frameworks.
- `workflows.md` -- Common multi-step workflows (issue a cert, verify a domain, etc.) that agents can follow.

## Authentication

All protected endpoints require:

```
Authorization: Bearer <api_key>
```

API keys start with `kk_` and are created via the `create_api_key` tool (requires an existing JWT session) or through the web dashboard.

## Quick Reference

The live OpenAPI spec is always available at `GET /swagger-json` on any running KrakenKey API instance. These tool definitions are a simplified, agent-friendly projection of that spec.
