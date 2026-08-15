# Agent Ops Local Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a local agent-ops stack: VK in Docker (localhost-only), `agent-ops/` rules/templates, Makefile bootstrap, and Phase 2 scripts for spawn + validate-dispatch.

**Architecture:** VK server runs in `docker-compose.local.yml` with host bind mounts for `~/.vk-data` and repos. Host agents (Claude/Cursor/AGY) coordinate via hcom + VK MCP. All orchestration rules live in `agent-ops/` and `.cursor/rules/agent-ops.mdc`.

**Tech Stack:** Docker Compose, Makefile, bash, Markdown rules, existing root `Dockerfile`, hcom, `npx vibe-kanban mcp`

**Spec:** [`docs/superpowers/specs/2026-08-15-agent-ops-local-design.md`](../specs/2026-08-15-agent-ops-local-design.md)

**Status:** Approved (@agent-ops-kona APPROVE 2026-08-15, conditional items synced in spec §7.2)

---

## File map

| File | Action | Responsibility |
|------|--------|----------------|
| `docker-compose.local.yml` | Create | VK local service, volumes, localhost port bind |
| `.env.agent-ops.example` | Create | Documented env vars for paths, hcom, AGY model |
| `Makefile` | Create | `up`, `down`, `status`, `logs`, Phase 2 targets |
| `agent-ops/base.md` | Create | Core orchestration rules (§6 of spec) |
| `agent-ops/capabilities/*.md` | Create | Role/purpose checklists |
| `agent-ops/templates/issue.md` | Create | VK issue template |
| `agent-ops/mcp/vibe-kanban.json` | Create | Host MCP config snippet |
| `agent-ops/hcom/message-formats.md` | Create | TASK/VERIFY/DISCUSS examples |
| `.cursor/rules/agent-ops.mdc` | Create | Cursor rule pointing at `agent-ops/` |
| `scripts/spawn-agents.sh` | Create | Preflight cursor+agy, spawn via hcom |
| `scripts/validate-dispatch.sh` | Create | Validate issue body fields |
| `scripts/tests/validate-dispatch.test.sh` | Create | Shell tests for validator |
| `docs/agent-ops/README.md` | Create | Quick start for humans |

---

## Phase 1 — Docker + Makefile + agent-ops content

### Task 1: Docker Compose local VK

**Files:**
- Create: `docker-compose.local.yml`
- Create: `.env.agent-ops.example`

- [ ] **Step 1: Create `.env.agent-ops.example`**

```env
# Vibe Kanban local Docker
VK_PORT=3000
# Leave VK_DATA_DIR / VK_REPOS_DIR unset to use the compose defaults
# (${HOME} expands correctly there). Compose reads --env-file literally and
# does NOT shell-expand ${HOME}, so only set these to ABSOLUTE paths:
# VK_DATA_DIR=/home/youruser/.vk-data
# VK_REPOS_DIR=/home/youruser/workspaces

# Container runs as this uid:gid so it can write the bind-mounted dirs.
# Must match the host user owning VK_DATA_DIR / VK_REPOS_DIR (`id -u`, `id -g`).
VK_UID=1000
VK_GID=1000

# Optional: mount single repo only (reduces blast radius)
# VK_REPO_MOUNT=/home/youruser/workspaces/myapp

# hcom room for this project
HCOM_TAG=myapp

# AGY (run: agy models)
AGY_MODEL=gemini-3.7-flash-low
AGY_MODEL_FALLBACK=gemini-3.6-flash-low

# Coordinator heuristic (minutes, not automated in Phase 1)
AGENT_ACK_TIMEOUT_MIN=30
```

- [ ] **Step 2: Create `docker-compose.local.yml`**

```yaml
services:
  vibe-kanban:
    build:
      context: .
      dockerfile: Dockerfile
    # Image runs as appuser uid 10001 (Dockerfile:133,142), but bind mounts keep
    # host ownership (uid 1000) and mask the Dockerfile's `chown /repos`.
    # Without this the server cannot create db.v2.sqlite or write git worktrees.
    user: "${VK_UID:-1000}:${VK_GID:-1000}"
    ports:
      - "127.0.0.1:${VK_PORT:-3000}:3000"
    environment:
      HOST: 0.0.0.0
      PORT: 3000
      VK_ALLOWED_ORIGINS: http://localhost:${VK_PORT:-3000}
    volumes:
      - ${VK_DATA_DIR:-${HOME}/.vk-data}:/home/appuser/.local/share/vibe-kanban
      - ${VK_REPOS_DIR:-${HOME}/workspaces}:/repos:rw
    # No healthcheck block: Dockerfile:149 already defines an identical one.
    restart: unless-stopped
```

Note: if `VK_REPO_MOUNT` is set in `.env.agent-ops`, document in README that user should replace the repos volume line manually (single-repo mount). Phase 1 keeps default full `VK_REPOS_DIR` mount; README documents optional override.

- [ ] **Step 3: Verify compose file parses and mounts resolve**

Run: `docker compose -f docker-compose.local.yml config --quiet`
Expected: exit 0 (no output)

Run: `docker compose -f docker-compose.local.yml config | grep -A2 'source:'`
Expected: absolute host paths — **no literal `${HOME}`** in any source

- [ ] **Step 4: Commit**

```bash
git add docker-compose.local.yml .env.agent-ops.example
git commit -m "feat(agent-ops): add local Docker Compose and env example"
```

---

### Task 2: Makefile Phase 1 targets

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create `Makefile`**

```makefile
COMPOSE_FILE := docker-compose.local.yml
ENV_FILE := .env.agent-ops
VK_PORT ?= 3000

.PHONY: up down status logs agents-up agents-down mcp-install validate-dispatch

up:
	@mkdir -p "$${VK_DATA_DIR:-$$HOME/.vk-data}" "$${VK_REPOS_DIR:-$$HOME/workspaces}"
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) up -d --build

down:
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) down

status:
	@curl -sf "http://127.0.0.1:$(VK_PORT)/health" && echo " VK health: OK" || echo " VK health: FAIL"
	@uvx hcom list 2>/dev/null || echo "hcom: not available"

logs:
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) logs -f

agents-up:
	@test -f scripts/spawn-agents.sh || (echo "run after Task 9" && exit 1)
	@bash scripts/spawn-agents.sh

agents-down:
	@echo "Run manually: uvx hcom stop tag:<HCOM_TAG>  (user-initiated only)"

mcp-install:
	@echo "=== Cursor / Claude: merge agent-ops/mcp/vibe-kanban.json into your MCP config ==="
	@cat agent-ops/mcp/vibe-kanban.json

validate-dispatch:
	@test -n "$(ISSUE)" || (echo "Usage: make validate-dispatch ISSUE=path/to/issue.md" && exit 1)
	@bash scripts/validate-dispatch.sh "$(ISSUE)"
```

- [ ] **Step 2: Copy example env for local use**

Run: `cp .env.agent-ops.example .env.agent-ops`
Expected: `.env.agent-ops` exists (gitignored if added to `.gitignore`)

- [ ] **Step 3: Add `.env.agent-ops` to `.gitignore` if not present**

```gitignore
.env.agent-ops
```

- [ ] **Step 4: Commit**

```bash
git add Makefile .gitignore
git commit -m "feat(agent-ops): add Makefile with up/down/status targets"
```

---

### Task 3: `agent-ops/base.md` — core rules

**Files:**
- Create: `agent-ops/base.md`

- [ ] **Step 1: Write `agent-ops/base.md`** (include all §6 + §14.2 rules from spec)

Required sections:
1. VK = source of truth; hcom = dispatch only
2. `role` + `purpose` per task packet (not fixed per agent)
3. Act same turn (VK MCP + hcom send together)
4. No busy-poll
5. Path mapping: `/repos/` → `$VK_REPOS_DIR/` before host file ops
6. Cross-vendor verify when roster allows; `cross_vendor_met` on close
7. Plan gate: PROPOSAL before >3 task fan-out
8. DISCUSS only after 2 VK rounds stuck; post conclusion to VK
9. ACK timeout = human heuristic (`AGENT_ACK_TIMEOUT_MIN`), not automated Phase 1
10. Read `agent-ops/capabilities/<role>.md` for current task

- [ ] **Step 2: Commit**

```bash
git add agent-ops/base.md
git commit -m "docs(agent-ops): add base orchestration rules"
```

---

### Task 4: Capability checklists

**Files:**
- Create: `agent-ops/capabilities/planner.md`
- Create: `agent-ops/capabilities/worker.md`
- Create: `agent-ops/capabilities/verifier.md`
- Create: `agent-ops/capabilities/reviewer.md`
- Create: `agent-ops/capabilities/explore.md`

- [ ] **Step 1: Write each file** (~15–25 lines each)

`planner.md`: decompose epic → VK child TASKs + hcom packets; no code edits.

`worker.md`: MCP `get_context` once; implement per acceptance; hcom ACK with diff summary.

`verifier.md`: run verify commands only; INFORM PASS/FAIL; cross-vendor preferred.

`reviewer.md`: judge PROPOSAL/DECISION on VK; APPROVE/REJECT/NEEDS_INFO comments.

`explore.md`: read-only; purpose explore/search; return structured findings.

- [ ] **Step 2: Commit**

```bash
git add agent-ops/capabilities/
git commit -m "docs(agent-ops): add role and purpose capability checklists"
```

---

### Task 5: Templates, MCP snippet, hcom formats

**Files:**
- Create: `agent-ops/templates/issue.md`
- Create: `agent-ops/mcp/vibe-kanban.json`
- Create: `agent-ops/hcom/message-formats.md`

- [ ] **Step 1: Copy issue template from spec §11.1 into `agent-ops/templates/issue.md`**

- [ ] **Step 2: Create MCP snippet** (from spec §8.2)

- [ ] **Step 3: Create `agent-ops/hcom/message-formats.md`** with full TASK, VERIFY, DISCUSS examples from spec §10.3–10.5

- [ ] **Step 4: Commit**

```bash
git add agent-ops/templates/ agent-ops/mcp/ agent-ops/hcom/
git commit -m "docs(agent-ops): add issue template, MCP snippet, hcom formats"
```

---

### Task 6: Cursor rule

**Files:**
- Create: `.cursor/rules/agent-ops.mdc`

- [ ] **Step 1: Create rule file**

```markdown
---
description: Agent-ops orchestration for VK + hcom multi-agent workflow
globs:
  - "**/*"
alwaysApply: true
---

# Agent Ops

You operate in the VK + hcom multi-agent stack.

Read and follow:
- `agent-ops/base.md` — always
- `agent-ops/capabilities/<role>.md` — from current task packet `role` field
- `agent-ops/capabilities/explore.md` — when `purpose` is explore or search

VK is source of truth. hcom is dispatch only. Translate MCP paths: `/repos/` → `$VK_REPOS_DIR/`.
```

- [ ] **Step 2: Commit**

```bash
git add .cursor/rules/agent-ops.mdc
git commit -m "feat(agent-ops): add Cursor rule for VK+hcom workflow"
```

---

### Task 7: Human README + smoke test Phase 1

**Files:**
- Create: `docs/agent-ops/README.md`

- [ ] **Step 1: Write quick start**

```markdown
# Agent Ops Local

1. `cp .env.agent-ops.example .env.agent-ops` and edit paths
2. `make up` — build and start VK at http://localhost:3000
3. Add VK project with path `/repos/<your-repo>`
4. Merge `agent-ops/mcp/vibe-kanban.json` into Cursor/Claude MCP config
5. `HCOM_TAG=myapp uvx hcom cursor` and `uvx hcom start --as myapp-claude` for Claude
6. `make status` — VK health + hcom list
```

Include WSL2 note: keep `VK_DATA_DIR` on Linux fs, not `/mnt/c/`.

- [ ] **Step 2: Smoke test (manual)**

Run: `make up`
Expected: container healthy, `curl http://127.0.0.1:3000/health` returns OK

Run: `make down`
Expected: container stopped

- [ ] **Step 3: Commit**

```bash
git add docs/agent-ops/README.md
git commit -m "docs(agent-ops): add quick start README"
```

---

## Phase 2 — Scripts (spawn + validate)

### Task 8: `validate-dispatch.sh` + tests

**Files:**
- Create: `scripts/validate-dispatch.sh`
- Create: `scripts/tests/validate-dispatch.test.sh`

- [ ] **Step 1: Write failing test**

`scripts/tests/validate-dispatch.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-dispatch.sh"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# valid minimal TASK issue
cat > "$TMP" <<'EOF'
## Role assignment
assign: @myapp-cursor
role: worker
purpose: implement
created_by: @myapp-claude
implementer_vendor: claude

## Acceptance
- [ ] tests pass

## Verify
command: cargo test
cross_vendor: true
EOF

bash "$VALIDATOR" "$TMP"
echo "valid case: OK"

# missing purpose should fail
cat > "$TMP" <<'EOF'
## Role assignment
assign: @myapp-cursor
role: worker
created_by: @myapp-claude
## Acceptance
- [ ] tests pass
## Verify
command: cargo test
cross_vendor: true
EOF

if bash "$VALIDATOR" "$TMP" 2>/dev/null; then
  echo "FAIL: should reject missing purpose"
  exit 1
fi
echo "invalid case: OK"
```

- [ ] **Step 2: Run test — expect FAIL** (validator not written)

Run: `bash scripts/tests/validate-dispatch.test.sh`
Expected: FAIL (file not found or validation passes incorrectly)

- [ ] **Step 3: Implement `scripts/validate-dispatch.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
FILE="${1:?Usage: validate-dispatch.sh <issue.md>}"
body=$(cat "$FILE")

check_field() {
  local pattern="$1"
  local msg="$2"
  echo "$body" | grep -qE "$pattern" || { echo "ERROR: $msg" >&2; exit 1; }
}

check_field 'assign:' 'missing assign'
check_field 'role:' 'missing role'
check_field 'purpose:' 'missing purpose'
check_field 'created_by:' 'missing created_by'
check_field '## Acceptance' 'missing Acceptance section'
check_field '- \[ \]' 'missing acceptance checkbox'
check_field '## Verify' 'missing Verify section'
check_field 'command:' 'missing verify command'
check_field 'cross_vendor: *(true|false)' 'missing cross_vendor'

if echo "$body" | grep -q 'purpose: implement'; then
  check_field 'implementer_vendor:' 'missing implementer_vendor for implement'
fi

echo "validate-dispatch: OK"
```

- [ ] **Step 4: Run test — expect PASS**

Run: `bash scripts/tests/validate-dispatch.test.sh`
Expected: `valid case: OK` and `invalid case: OK`

- [ ] **Step 5: Commit**

```bash
chmod +x scripts/validate-dispatch.sh scripts/tests/validate-dispatch.test.sh
git add scripts/validate-dispatch.sh scripts/tests/validate-dispatch.test.sh
git commit -m "feat(agent-ops): add validate-dispatch script with tests"
```

---

### Task 9: `spawn-agents.sh`

**Files:**
- Create: `scripts/spawn-agents.sh`

- [ ] **Step 1: Write script**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env.agent-ops"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

HCOM_TAG="${HCOM_TAG:-myapp}"
AGY_MODEL="${AGY_MODEL:-gemini-3.7-flash-low}"
AGY_MODEL_FALLBACK="${AGY_MODEL_FALLBACK:-gemini-3.6-flash-low}"
BASE_PROMPT="$ROOT/agent-ops/base.md"

echo "=== Roster preflight (spawned agents only) ==="
for bin in cursor-agent agy; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo "  OK  $bin"
  else
    echo "  MISSING  $bin"
  fi
done
if command -v claude >/dev/null 2>&1; then
  echo "  INFO claude (user session, not spawned here)"
fi

echo "=== Spawning into room: $HCOM_TAG ==="
export HCOM_TAG
HCOM_TAG="$HCOM_TAG" uvx hcom cursor

if HCOM_TAG="$HCOM_TAG" uvx hcom agy --model "$AGY_MODEL" \
  --hcom-system-prompt "$(cat "$BASE_PROMPT")"; then
  echo "AGY spawned with $AGY_MODEL"
else
  echo "WARN: AGY spawn failed with $AGY_MODEL, retrying $AGY_MODEL_FALLBACK"
  HCOM_TAG="$HCOM_TAG" uvx hcom agy --model "$AGY_MODEL_FALLBACK" \
    --hcom-system-prompt "$(cat "$BASE_PROMPT")"
fi

echo "Claude: run in your session: uvx hcom start --as ${HCOM_TAG}-claude"
```

- [ ] **Step 2: Make executable and dry-run preflight section**

Run: `bash -n scripts/spawn-agents.sh && echo syntax OK`

- [ ] **Step 3: Commit**

```bash
chmod +x scripts/spawn-agents.sh
git add scripts/spawn-agents.sh
git commit -m "feat(agent-ops): add spawn-agents script with roster preflight"
```

---

### Task 10: End-to-end verification checklist

- [ ] **Step 1: Full stack smoke**

```bash
cp .env.agent-ops.example .env.agent-ops   # if not exists, then set VK_UID/VK_GID to `id -u`/`id -g`
make up
make status                                 # VK health OK
bash scripts/tests/validate-dispatch.test.sh   # not the raw template: it has
                                               # placeholder values and passes falsely
make down
```

- [ ] **Step 1b: Confirm the container actually wrote to the bind mounts**

Run: `ls "$(grep -s VK_DATA_DIR .env.agent-ops | cut -d= -f2 || echo ~/.vk-data)"`
Expected: `db.v2.sqlite` present and owned by your host user.
If empty or permission errors in `make logs`: `VK_UID`/`VK_GID` do not match the
owner of the mounted dirs. This is the first thing to check — the image's own
user is uid 10001, which cannot write host-owned directories.

- [ ] **Step 2: Document verification in `docs/agent-ops/README.md`** — add "Verification" section with commands above

- [ ] **Step 3: Final commit**

```bash
git add docs/agent-ops/README.md
git commit -m "docs(agent-ops): add verification checklist"
```

---

## Spec coverage checklist

| Spec section | Task |
|--------------|------|
| §6 Orchestration principles | Task 3 `base.md` |
| §6.8 Path mapping | Task 3 `base.md` |
| §6.9 Planner role | Task 4 `planner.md` |
| §7 Docker local | Task 1 |
| §8 MCP snippet | Task 5 |
| §9 Role vs purpose | Task 4 capabilities |
| §10 hcom formats | Task 5 |
| §11 Issue template + validate | Task 5, Task 8 |
| §14 agent-ops structure | Tasks 3–6 |
| §15 Makefile bootstrap | Task 2, Task 9 |
| §18 WSL2 error note | Task 7 README |
| §19 Security localhost bind | Task 1 compose |

## Plan self-review

- [x] All spec Phase 1 + Phase 2 files have tasks
- [x] No TBD placeholders
- [x] `validate-dispatch` has executable test
- [x] Paths match spec exactly
- [x] YAGNI: no path-map.sh, no auth middleware, no cao-server, no duplicate healthcheck
- [x] Container uid matches bind-mount owner (`VK_UID`/`VK_GID`) — image user is 10001, host is not
- [x] Env-file values are absolute; `${HOME}` expansion left to compose defaults

---

## Execution options

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks

**2. Inline Execution** — execute in this session with executing-plans checkpoints

---

## Review log — @agent-ops-kona (2026-08-15)

**Initial verdict:** REVISE — patches applied directly by Kona + Cursor ack

| # | Finding | Resolution |
|---|---------|------------|
| 1 | **Blocker:** UID 10001 vs host 1000 on bind mounts | `user: "${VK_UID}:${VK_GID}"` in compose; `VK_UID`/`VK_GID` in env example |
| 2 | Validator missing `cross_vendor:` | Added to Task 8 script + test |
| 3 | `agents-up` wrong task number | Fixed → Task 9 |
| 4 | Task 10 false-positive on template | Use `validate-dispatch.test.sh` + step 1b db write check |
| 5 | `${HOME}` in env file not expanded | Documented; leave unset, use compose defaults |
| 6 | Duplicate healthcheck | Removed from compose (Dockerfile has one) |

**Pending:** ~~Kona final APPROVE~~ **APPROVE** (conditional) — spec §7.2 synced by Kona (UID override, env-file caveat, no duplicate healthcheck).
