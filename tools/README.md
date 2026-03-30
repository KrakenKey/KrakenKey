# KrakenKey AI Agent Skills

Structured tool and workflow definitions for AI agents to interact with KrakenKey.

## Available Skills

### [krakenkey-api](krakenkey-api/)

REST API tool definitions covering all KrakenKey endpoints: certificate lifecycle, domain management, endpoint monitoring, probe management, organizations, and billing. Includes multi-step workflow guides.

Use this when an agent needs to make HTTP requests to the KrakenKey API.

### [krakenkey-cli](krakenkey-cli/)

CLI tool definitions for the `krakenkey` command-line interface. Covers all commands: auth, domain, cert, endpoint, and account. Includes workflow guides and scripting patterns.

Use this when an agent needs to run `krakenkey` CLI commands in a terminal.

## Structure

Each skill directory contains:

- `README.md` -- Overview and authentication info
- `tool-definitions.json` -- Machine-readable tool definitions (parameters, types, examples)
- `workflows.md` -- Multi-step workflow guides for common tasks
