# KrakenKey CLI Tools for AI Agents

Structured tool definitions for AI agents to use the `krakenkey` CLI for TLS certificate management and endpoint monitoring.

## Files

- `tool-definitions.json` -- Machine-readable tool definitions with commands, flags, and output formats.
- `workflows.md` -- Common multi-step workflows using the CLI.

## Authentication

The CLI requires an API key. Set it up with:

```bash
krakenkey auth login --api-key kk_...
```

Or set the `KK_API_KEY` environment variable.

## Output Formats

- **Text mode** (default): Human-readable tables and colored status messages
- **JSON mode** (`--output json`): Machine-readable JSON, suitable for piping to `jq` or parsing programmatically

When using the CLI from an AI agent, prefer `--output json` for structured data.
