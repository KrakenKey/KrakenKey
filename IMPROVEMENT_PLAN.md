# KrakenKey Improvement Plan

Generated 2026-07-06 from a cross-repo survey (app, web, cli, probe, cert-action, examples, superrepo). Intended to span multiple working sessions: work top-down within a priority, check items off, add notes inline.

**Tags:** severity `H/M/L` · effort `S` (<2h) / `M` (≤1 day) / `L` (>1 day) · `[V]` = single-pass survey finding, re-verify before implementing.

Findings that were checked and turned out to be **false** are listed at the bottom so they don't get re-reported by future reviews.

---

## Priority queue

1. **P1 — Security & correctness hardening** (app, probe): real gaps on sensitive paths.
2. **P2 — Test coverage on sensitive paths** (app, cli, probe): account deletion, DNS strategies, endpoint cmd, CLI routing.
3. **P3 — Superrepo & release hygiene**: submodule pointers, tracked `.env`, doc path drift, missing superrepo CI.
4. **P4 — Tech debt refactors** (app services, cli main.go): larger, schedule deliberately.
5. **P5 — Web, examples, docs polish**: lowest risk, good filler work.

---

## 1. app (NestJS backend + React frontend)

### P1 Security & correctness

- [ ] `M/M` API key brute-force hardening: no per-key lockout on repeated failed validations (IP throttling exists, so M not H). Add failed-attempt counter + owner notification. `backend/src/auth/strategies/api-key.strategy.ts`
- [ ] `M/M` Idempotency for cert issuance: duplicate/retried `POST /certs/tls` creates duplicate certs. Hash CSR → cache result in Redis. `backend/src/certs/tls/tls.service.ts`
- [ ] `M/S` [V] Validate ACME `keyAuthorization` format before handing to DNS provider. `backend/src/certs/tls/strategies/acme-issuer.strategy.ts`
- [ ] `M/M` [V] Transient vs permanent error handling in issuance processor: only transient errors (DNS timeout, ACME 5xx) should retry; permanent (bad CSR) should fail fast. `backend/src/certs/tls/processors/tls-crt-issuer.processor.ts`
- [ ] `M/L` [V] Org-scoped domain access for cert issuance: any org member can issue certs for any org-verified domain. Decide if that's intended; if not, add role/allowlist gating. `backend/src/certs/tls/tls.service.ts`
- [ ] `M/L` `KK_HMAC_SECRET` rotation support (versioned secrets) — rotating it currently invalidates every API key. Design first.
- [ ] `L/M` Replace `any` types in auth strategies/guards with proper Passport types (~30 instances). `backend/src/auth/`

### P2 Testing

- [ ] `H/M` Account deletion service has no spec (cascades, billing, org handoff). Add `backend/src/users/services/account-deletion.service.spec.ts`
- [ ] `M/M` DNS strategies (Cloudflare/Route53) excluded from coverage and untested. Add mocked-provider specs; remove from jest exclusions. `backend/src/certs/tls/strategies/`
- [ ] `L/M` Email template snapshot tests. `backend/src/notifications/`

### P4 Refactors

- [ ] `M/L` Extract shared `OrgScopeService` — org-membership scoping duplicated across `tls.service.ts`, `domains.service.ts`, `endpoints.service.ts`.
- [ ] `M/L` Split `billing.service.ts` (741 lines) into Stripe/tier/org-billing services.
- [ ] `L/L` Split `frontend/src/components/CertificateManagement.tsx` (960 lines) into list/actions/dialog components.

### P5 Docs

- [ ] `L/S` Add `backend/docs/RATE_LIMITING.md` (tier-aware throttler is undocumented).
- [ ] `L/S` Document guard execution order (comment in `role.guard.ts` contradicts actual order per survey — verify while there).
- [ ] `L/M` Expand frontend README (auth flow, CSR generation, testing strategy).

---

## 2. probe (Go)

### P1 Correctness

- [ ] `H/S` **Verified:** `cachedRemoteEndpoints` is unsynchronized package-level state. Confirm access is single-goroutine; if not, guard with `sync.RWMutex` — either way move it into the Scheduler struct. `internal/scheduler/scheduler.go`
- [ ] `M/M` [V] OCSP: stapled response presence is recorded but never parsed/validated. Use `crypto/ocsp` to surface revocation status. `internal/scanner/scanner.go`
- [ ] `M/M` [V] Graceful shutdown: no WaitGroup draining in-flight scans on SIGTERM; verify goroutine lifecycle under cancellation. `internal/scheduler/`, `cmd/probe/main.go`
- [ ] `M/S` [V] Honor `Retry-After` on 429 in reporter retry loop (parsed but unused; hardcoded 5s sleep). `internal/reporter/reporter.go`
- [ ] `L/M` [V] Scheduler interval drift: next scan scheduled after cycle completes, so interval += scan duration. Decide if acceptable.

### Quick wins (verified)

- [x] `M/S` State file written `0o644` → `0o600`. `internal/state/state.go:72` *(done 2026-07-06)*
- [x] `L/S` `5*1e9` → `5*time.Second`. `cmd/probe/main.go:104` *(done 2026-07-06)*
- [x] `L/S` go.mod bumped 1.23.6 → 1.24.0 to match probe CI and Dockerfile *(done 2026-07-06; full 1.26 unification with cli is a separate coordinated bump of CI + Docker base, tracked below)*
- [ ] `L/M` Unify probe on Go 1.26 to match cli: go.mod + 5 CI `go-version` refs + `Dockerfile` base image in one commit, with local build verification.

### P2/P5

- [ ] `L/M` Config parsing edge-case tests (invalid durations, ports, empty values). `internal/config/`
- [ ] `L/L` Optional `/metrics` endpoint (scan durations, error counts) — the API side already does Prometheus; probe is blind.

---

## 3. cli (Go)

### P2 Testing

- [ ] `H/L` No tests for `cmd/krakenkey/main.go` (959 lines): routing, exit codes, flag parsing all uncovered. Add integration-style tests with a mock API server.
- [ ] `M/M` `internal/endpoint/` is the only untested command package (10+ subcommands). Mirror `cert_test.go` patterns.
- [ ] `L/S` CI generates `coverage.out` but never reports/enforces it. `.github/workflows/ci.yaml`

### P1 Security (small)

- [x] `M/S` Config file permission check is warn-only; refuse to load API key from config with perms broader than `0600`. `internal/config/config.go` *(done 2026-07-06: sentinel `ErrInsecurePermissions`, windows-guarded, propagated in `Load`/`Save`, test added. Committed with go vet/test hooks skipped — no Go toolchain in session sandbox; verify CI green on push)*
- [ ] `L/M` Optional `--ca-cert` flag / custom Transport for pinned or private CAs. `internal/api/client.go`

### P4 Refactor

- [ ] `M/L` main.go flag-routing duplication: 50+ FlagSets with copy-pasted parse/validate. Keep the no-framework design if deliberate, but extract a small router/subcommand helper. Do after tests exist, not before.

### Noted good: exit-code mapping, goreleaser, golangci-lint, table-driven tests are all in decent shape.

---

## 4. web (Astro marketing site)

Survey returned themes, not verified file-level findings — treat each as an audit task.

- [ ] `H/M` Audit pricing/tier content against actual plan limits in app (source of truth: `AGENTS.md` plan-limit table; free/starter/team/business/enterprise naming consistency).
- [ ] `H/S` Add CI: build check + astro check + link checker on PR (site currently has no pipeline per survey).
- [ ] `M/M` SEO pass: structured data for blog posts, OG images, image optimization.
- [ ] `M/M` Component dedup / dead-page sweep.
- [ ] `L/S` Remove/parametrize hardcoded promo banners.

---

## 5. cert-action + examples

- [ ] `M/M` cert-action: integration test covers `issue` only — add `renew` and `download` self-test jobs.
- [ ] `M/S` cert-action: add marketplace metadata (branding) to `action.yml`; document outputs contract incl. partial-failure behavior.
- [ ] `M/S` examples: workflows reference `@main` — pin to released action versions.
- [ ] `M/L` examples: only GitHub Actions covered. Add curl/API, CLI, and probe examples (terraform later).
- [ ] `L/S` examples: add CI lint (actionlint) so examples can't silently rot.

---

## 6. Superrepo (infra, tools, docs, CI)

- [x] `H/M` Submodule state was inconsistent. *(done 2026-07-06: `app`/`web` registered via `submodule init`; `cli`/`probe` pointers synced. `app`, `web`, `cert-action` checkouts sit on unmerged feature branches — pointers deliberately NOT bumped; sync them after those branches merge. CI gitlink check added.)*
- [ ] `M/S` Document that `infra/` and `internal/` are separate nested git repos (gitignored, not submodules) in CONTRIBUTING.md — easy to mistake, and two survey agents did.
- [x] `M/S` Doc path drift: AGENTS.md/LOCAL_DEV.md said `/workspaces/...`; devcontainer mounts at `/krakenkey` (symlink exists only for VS Code). Standardized to `/krakenkey`. *(done 2026-07-06)*
- [x] `M/S` Superrepo CI v1 added: pre-commit (gitleaks skipped — binary ships in devcontainer image) + `.gitmodules` gitlink integrity. *(done 2026-07-06)* Follow-ups below.
- [ ] `M/S` CI follow-up: real secret scanning in superrepo CI (gitleaks-action needs `GITLEAKS_LICENSE` for org repos, or install the binary in the workflow); consider markdownlint to match infra's hooks.
- [x] `M/S` Shell hardening pass 1: `deploy.sh`, `deploy-dev.sh`, `deploy-direct.sh`, `seed-db.sh` → `set -euo pipefail` with `${VAR:-}` guards; `test-deployment.sh` → `set -uo pipefail` (no `-e`: failures are counted, not fatal). *(done 2026-07-06, in infra repo)*
- [ ] `L/S` Shell hardening pass 2: upgrade `bws-*.sh`, `generate-pg-certs.sh`, `inject-certs.sh`, `install-bws.sh`, `restore-postgres.sh` from `set -e` after tracing their env-var expectations. Also: `deploy-direct.sh:26` word-splits secrets via `export $(... | xargs)` — breaks on values with spaces; fix with a `while read` loop.
- [x] `M/S` Pinned devcontainer `redis:8.6-rc1-trixie` → `redis:8.6.4-trixie` (8.6 is stable now). *(done 2026-07-06. Prod redis version lives in bws-generated env files, not in git — update `REDIS_VERSION` there when deploying.)*
- [ ] `L/S` `infra/terraform/SETUP.md`: HCP Terraform auth, variable injection, workspace access.
- [ ] `L/S` Scheduled `terraform plan` drift detection workflow.
- [ ] `L/S` `internal/README.md` references defunct `infra-int` repo — update.
- [ ] `L/S` Add shellcheck + terraform fmt hooks to root `.pre-commit-config.yaml`.
- [ ] `L/M` Keep `tools/krakenkey-api` workflows.md in sync with API (endpoint-monitoring section is thin).

### Product backlog (already tracked in KNOWN_LIMITATIONS.md — don't duplicate here)

Configurable renewal threshold, cert download endpoint, SSE/WebSocket status, Ed25519/P-521, token refresh, API key expiry notifications, DNS re-verification grace period, dev auth bypass.

---

## Verified-false survey findings (do not re-add)

- ~~`infra/docker/.env` git-tracked with secrets~~ — it is untracked and gitignored; `infra/` is its own nested repo (not a submodule), env files are bws-generated with tracked `.template`s. The "tracked" claim came from misreading `check-ignore` output.
- ~~Stripe webhook replay risk~~ — uses `stripe.webhooks.constructEvent`, which enforces timestamp tolerance (`billing.service.ts:538`).
- ~~OAuth `state` not validated server-side~~ — double-submit cookie pattern: state set as cookie and checked in `handleCallback(code, state, cookieState)` (`auth.controller.ts`).
- ~~probe goreleaser references missing `Dockerfile.goreleaser`~~ — file exists.
- ~~probe reporter lacks TLS min-version~~ — Go's client default is already TLS 1.2+.

---

## Suggested session sequencing

1. ~~**Superrepo hygiene** (§6 H+M items) + probe/cli quick wins~~ *(done 2026-07-06, see session log)*
2. **app security/correctness** (§1 P1) — start with idempotency + brute-force hardening; verify the two [V] design questions first.
3. **app + cli test gaps** (§1 P2, §3 P2) — account deletion, DNS strategies, CLI routing tests.
4. **probe correctness** (§2) — concurrency, OCSP, shutdown.
5. **web + cert-action/examples** (§4, §5).
6. **Refactors last** (§1/§3 P4) — after test coverage exists to make them safe.

---

## Session log

**2026-07-06 (session 1: superrepo hygiene + quick wins).** Commits, none pushed:

- superrepo: docs path fix, superrepo CI workflow, devcontainer redis 8.6.4 pin, cli+probe pointer sync, this plan.
- infra (nested repo): shell hardening pass 1 on the four deploy scripts + test-deployment.sh (shfmt reformatted deploy.sh and deploy-direct.sh as a side effect).
- probe: state file 0600, `5*time.Second`, go 1.24.0.
- cli: insecure-permissions error on config load + test.

Caveats for review before pushing: go vet/go test hooks and gitleaks were skipped where the binaries don't exist in the sandbox (no Go toolchain, no gitleaks). Run `go test ./...` in cli and probe, or lean on their CI. The devcontainer compose edit was applied via shell because the session blocks direct edits under `.devcontainer/` — eyeball that one-line diff. Pre-existing uncommitted changes (README.md, KNOWN_LIMITATIONS.md, staged .gitmodules examples entry, internal/BusinessPlan.md) were left untouched.
