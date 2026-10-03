# KrakenKey CLI Tools for AI Agents

Structured tool definitions for AI agents to use the `krakenkey` CLI (v0.5.0) for TLS certificate management and endpoint monitoring.

## Files

- `tool-definitions.json` -- Machine-readable tool definitions with commands, flags, defaults, and examples.
- `workflows.md` -- Common multi-step workflows using the CLI.

## Installation

Pre-built binaries are on [GitHub Releases](https://github.com/KrakenKey/cli/releases) for Linux and macOS (amd64, arm64) and Windows (amd64). Archives are named `krakenkey_<version>_<os>_<arch>.tar.gz` (`.zip` on Windows), for example `krakenkey_0.5.0_linux_amd64.tar.gz`.

```bash
# go install
go install github.com/krakenkey/cli/cmd/krakenkey@latest

# From source (Go 1.26)
git clone https://github.com/KrakenKey/cli.git && cd cli
go build -o krakenkey ./cmd/krakenkey

# Container image
docker pull ghcr.io/krakenkey/cli:latest
```

`krakenkey version` prints `krakenkey-cli <version>`. Source builds without `-ldflags "-X main.version=..."` report `dev`.

## Authentication

Every API command needs a user API key (`kk_...`). Provide it one of three ways:

```bash
# 1. Environment variable (good for CI and agents)
export KK_API_KEY=kk_...

# 2. Global flag, per invocation
krakenkey --api-key kk_... domain list

# 3. Save it to the config file (checked against the API before saving)
krakenkey auth login --api-key kk_...
krakenkey auth login            # prompts for the key on stdin
```

Precedence, highest first: flag, env var, config file, default.

### Config file

`~/.config/krakenkey/config.yaml` (or `$XDG_CONFIG_HOME/krakenkey/config.yaml`), written with mode `0600`:

```yaml
api_url: https://api.krakenkey.io
api_key: kk_...
output: text
```

On non-Windows systems the CLI refuses to load or save this file if its permissions are broader than `0600` (any group or other bits set). Commands then fail with exit code 5 before contacting the API. Fix it with:

```bash
chmod 600 ~/.config/krakenkey/config.yaml
```

## Global Flags

Global flags must come **before** the command: `krakenkey --output json cert list`, not `krakenkey cert list --output json`.

| Flag | Env var | Default | Description |
|------|---------|---------|-------------|
| `--api-url` | `KK_API_URL` | `https://api.krakenkey.io` | API base URL |
| `--api-key` | `KK_API_KEY` | | API key |
| `--output` | `KK_OUTPUT` | `text` | `text` or `json` |
| `--no-color` | `NO_COLOR` (any value) | off | Disable ANSI colors |
| `--verbose` | | off | Accepted but currently has no effect |
| `--version` | | | Print version and exit |

## Output Formats

- **JSON** (`--output json` or `KK_OUTPUT=json`): indented JSON on stdout, nothing else. Command errors go to stderr as `{"error":"..."}`; a config load failure is printed as plain text. Commands that have no response body (`auth login`, `auth logout`, `auth keys delete`, `domain delete`, `cert delete`, `endpoint delete`, `endpoint region remove`, `endpoint probe remove`) print nothing on success; check the exit code.
- **Text** (default): status lines, aligned tables, and a spinner on stderr while `--wait` polls. Current builds also print the raw JSON response on stdout in text mode, so never parse text output.

Agents should always use `--output json` (or set `KK_OUTPUT=json`) and parse stdout with `jq` or a JSON parser.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error: API errors other than 401/404/429 (validation, plan limits), network failures, bad flags, unknown command, issuance or renewal failed, `--wait` timed out |
| 2 | API returned 401 (API key rejected) |
| 3 | API returned 404 |
| 4 | API returned 429 (rate limited) |
| 5 | Configuration or usage error: insecure config file permissions, missing required flag or argument, non-integer certificate ID, `auth status` with no key configured |

`cert issue` and `cert submit` wrap errors from the submit request, so a 401, 404, or 429 at that step exits 1, not 2, 3, or 4.
