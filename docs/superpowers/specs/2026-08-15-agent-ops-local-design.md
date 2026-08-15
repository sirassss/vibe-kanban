# Agent Ops Local — Design Spec

**Date:** 2026-08-15  
**Updated:** 2026-08-15 (CAO + Omnigent/Polly patterns; REVISE pass per @agent-ops-kona review)  
**Status:** Approved (Kona APPROVE 2026-08-15; final nits applied)  
**Scope:** Local Vibe Kanban (Docker) + multi-agent coordination (hcom + MCP) with flexible per-task roles

**References reviewed:**

- [CAO (cli-agent-orchestrator)](https://github.com/awslabs/cli-agent-orchestrator) — inbox-driven coordination, agent profiles, workflow validate gate
- [Omnigent Polly](https://github.com/omnigent-ai/omnigent/tree/main/examples/polly) — `purpose`-based dispatch, cross-vendor review, plan gate, act-same-turn

---

## 1. Summary

This spec defines a local development operations stack for coordinating Claude, Cursor, and AGY agents around **Vibe Kanban (VK)** as the task source of truth, with **hcom** for dispatch, notifications, and time-boxed technical debates.

Key properties:

- **VK in Docker** — isolates the VK server from the host environment.
- **Agents on host** — Claude, Cursor, and AGY run outside Docker (IDE, git, hcom hooks).
- **Data on host** — SQLite DB and git repos are bind-mounted so data survives container restarts.
- **Flexible roles** — `role` and `purpose` are assigned **per task** in a task packet, not fixed per agent type.
- **Kanban-first escalation** — proposals and decisions live on VK; hcom `DISCUSS` is a fallback when the board cannot resolve an issue in two comment rounds.
- **Inbox-driven, no poll** — agents wait for hcom delivery; they do not busy-poll VK or hcom when idle.
- **Phased bootstrap** — Makefile Phase 1 (VK up/down/status); Phase 2 (agent spawn with preflight, MCP installer, room reset).

---

## 2. Goals

| Goal | Success criteria |
|------|------------------|
| Environment isolation | VK server runs in Docker; host Rust/Node versions do not affect VK |
| Data durability | DB and repos persist on host across `docker compose down` |
| Low token cost | Structured issue templates; MCP `get_context` once per task; short hcom acks |
| Flexible assignment | Any agent can create, assign, or execute tasks via VK + hcom |
| Clear escalation | PROPOSAL → review on VK → TASK; stuck → DISCUSS on hcom → conclusion on VK |
| Cross-vendor quality | Verifier/reviewer prefers a different agent vendor than implementer when possible |
| Multi-repo ready | Single VK instance; one hcom tag per project slug; start with one repo |

## 3. Non-goals

- Self-hosting VK Cloud (`crates/remote` Docker stack) — out of scope; this is **local VK** only.
- Containerising agents — agents stay on host.
- Running CAO server or Omnigent server — borrow patterns only, not full stacks.
- Polly-style one-PR-per-subtask by default — optional for large fan-outs; not required for small tasks.
- Fully automated CI/CD for agent workflows — Phase 1 is manual/semi-auto bootstrap.
- Replacing VK issue tracker with hcom messages — hcom is coordination only.

---

## 4. Design influences (CAO + Polly)

Patterns adopted from reference orchestrators and how they map here:

| Pattern | Source | Agent-ops adaptation |
|---------|--------|----------------------|
| **Inbox-driven coordination** | CAO event bus + inbox; Polly `sys_read_inbox` | hcom hooks deliver messages; agents do not poll |
| **Agent profiles / flexible dispatch** | CAO `developer`, `reviewer` profiles | `role` + `purpose` in task packet (per task) |
| **Purpose-based dispatch** | Polly `implement` / `review` / `explore` / `search` | `purpose` field in packet and VK issue |
| **Cross-vendor review** | Polly cross-review skill | Verifier/reviewer ≠ implementer vendor when possible |
| **Plan gate** | Polly pulls human before large fan-out | VK `[PROPOSAL]` before multi-task dispatch |
| **Act same turn** | Polly: announce + dispatch in one turn | Create VK issue + hcom send in same agent turn |
| **Validate before run** | CAO `cao workflow validate` | `make validate-dispatch` checks issue template fields |
| **User approves large runs** | CAO: workflows never auto-run | Fan-out >3 tasks requires human ACK on VK PROPOSAL |
| **Task registry** | Polly `.polly/registry.json` | VK issues + status (single source of truth) |
| **Roster preflight** | Polly checks CLIs on PATH | `spawn-agents.sh` checks claude, cursor, agy before spawn |
| **No busy-poll** | Both: wait for inbox wake | Idle agents cost zero tokens until hcom delivers |
| **Failure recovery** | Polly: re-dispatch fresh, cancel runaway | FAIL ≥2 → DECISION; do not loop re-prompt same agent |

**Explicitly not adopted:**

- CAO `cao-server` or Omnigent session server — hcom + VK MCP are sufficient for local scope.
- Omnigent `sys_session_send` / worktree-per-PR fan-out — VK workspaces cover worktree needs; PR-per-task is optional.

---

## 5. Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ HOST                                                              │
│                                                                   │
│  Claude (session) ──┐                                             │
│  Cursor           ──┼── hcom room @<project-slug>                 │
│  AGY              ──┘    dispatch · ack · NOTIFY · DISCUSS      │
│         │              (inbox-driven — no busy-poll)              │
│         └── MCP stdio ──► http://127.0.0.1:3000 (VK API)        │
│                                                                   │
│  ~/workspaces/<repo>  ◄──bind──► /repos/<repo>  (in container)   │
│  ~/.vk-data/          ◄──bind──► VK SQLite + config             │
└──────────────────────────────────────────────────────────────────┘
                              ▲
                              │ :3000
                    ┌─────────┴──────────┐
                    │ Docker: vibe-kanban │
                    │  server + UI + DB   │
                    └────────────────────┘
```

### 5.1 Component responsibilities

| Component | Responsibility |
|-----------|----------------|
| **Vibe Kanban (Docker)** | Issue Kanban, workspaces, git worktrees, UI, SQLite (task registry) |
| **VK MCP** (`npx vibe-kanban mcp`) | CRUD issues, workspaces, `get_context` |
| **hcom** | Inbox-style dispatch, ack, notify, DISCUSS (not source of truth) |
| **agent-ops/** | Shared rules, capability checklists, issue templates, MCP snippets |
| **Makefile + scripts** | Bootstrap VK, validate dispatch, spawn agents with preflight |

### 5.2 Default capability hints (not fixed roles)

These are **hints** for assignment decisions. Actual behaviour comes from `role` + `purpose` in the task packet.

| Agent | Vendor | Strong at | Weak at | Default AGY model |
|-------|--------|-----------|---------|-------------------|
| Claude | Anthropic | Planning, review, adjudication, complex decisions | — | — |
| Cursor (Composer 2.5) | Cursor | Implementation, multi-file refactor | Mechanical verify | — |
| AGY | Google/Gemini | Verify, small scoped tasks with explicit spec | Ambiguous design | `gemini-3.7-flash-low` (verify), `gemini-3.7-flash-medium` (small implement) |

Run `agy models` periodically; prefer newest `gemini-3.7-flash-*` tier unless task needs Pro.

### 5.3 Cross-vendor rule (from Polly)

When assigning **verify** or **review** purpose:

1. Prefer an agent from a **different vendor** than the implementer.
2. Examples:
   - Cursor implemented → verify with AGY or Claude
   - AGY implemented → verify with Cursor or Claude
   - Claude implemented → verify with Cursor or AGY
3. If only one vendor is available (preflight roster), document the exception in the VK issue comment.

---

## 6. Orchestration principles

Rules borrowed from CAO and Polly that all agents must follow (also in `agent-ops/base.md`):

### 6.1 Act same turn (Polly)

If an agent announces it will create an issue or dispatch work, it **must** perform the VK MCP write and hcom send **in the same turn**. Announcing intent without tool calls is a dropped turn.

### 6.2 No busy-poll (CAO + Polly)

- Do not loop on `hcom poll` or repeatedly read VK status when waiting for another agent.
- Idle agents on hcom cost no tokens until a message arrives.
- Only use `hcom start` on agents that actively coordinate (typically Claude session); workers react to incoming messages.

### 6.3 Kanban-first, hcom-second

- All task state, specs, and decisions live on VK.
- hcom carries short dispatch, ack, and time-boxed debate only.
- After any hcom `DISCUSS`, post the conclusion to the linked VK issue (mandatory).

### 6.4 Validate before dispatch (CAO)

Before sending a TASK packet for non-trivial work, run `make validate-dispatch ISSUE=VK-142` (Phase 2) or manually confirm the issue body contains all required fields (see §8.1).

### 6.5 Plan gate (Polly)

Before dispatching **more than 3 parallel tasks** or a large epic:

1. Create `[PROPOSAL]` on VK with task breakdown.
2. Wait for human or Claude reviewer `APPROVE` on VK.
3. Only then send hcom TASK packets.

### 6.6 User approves large fan-out (CAO)

Automated agents must not fan out >3 tasks without explicit human approval on the linked VK PROPOSAL issue.

### 6.7 Failure recovery (Polly)

| Situation | Action |
|-----------|--------|
| Verify FAIL once | Re-dispatch same worker with error log |
| Verify FAIL twice | Create `[DECISION]` or assign Claude reviewer |
| Worker stuck / wrong approach | Cancel hcom thread if needed; fresh dispatch with revised spec — do not loop vague re-prompts |
| Empty or unclear ACK | Read VK issue + `hcom transcript` before re-dispatch |
| **No ACK within timeout** | Default **30 minutes** (`AGENT_ACK_TIMEOUT_MIN` in `.env.agent-ops`) — **heuristic for human/coordinator only** in Phase 1 (no automated watcher); coordinator sends hcom NOTIFY + VK comment if they notice; treat as FAIL unless assignee responds |
| **Agent offline / crashed** | `hcom list` shows not listening → NOTIFY room; reassign task or wait for human; do not busy-poll |

### 6.8 Path mapping — container ↔ host (required)

VK in Docker uses **container paths** (`/repos/...`). Host agents use **host paths** (`$VK_REPOS_DIR/...`). MCP responses (`get_context`, workspace paths) may return container paths.

**Rule (in `agent-ops/base.md`):** before any host file/git operation, translate paths:

| Direction | Rule |
|-----------|------|
| Container → host | Replace prefix `/repos/` with `$VK_REPOS_DIR/` (trailing slashes normalized) |
| Host → VK MCP | When creating projects/workspaces via API, use `/repos/<name>` not host absolute path |

Example: MCP returns `/repos/myapp/src/foo.ts` → host agent edits `$VK_REPOS_DIR/myapp/src/foo.ts`.

**Note:** VK uses `SqliteJournalMode::Delete` (see `crates/db/src/lib.rs`) — not configurable via env. Keep `VK_DATA_DIR` on a Linux filesystem (especially on WSL2; avoid `/mnt/c/...`) to reduce I/O risk.

### 6.9 When to use `role: planner`

`role: planner` is for **decomposition and dispatch only** — no implementation:

| Trigger | Example packet |
|---------|----------------|
| Human asks to break an epic | Claude: `role: planner`, `purpose: explore` → output child TASK list on VK |
| After PROPOSAL APPROVE | Planner creates child `[TASK]` issues + hcom dispatch packets |
| Re-plan after FAIL ≥ 2 | Planner revises spec on VK, re-dispatches worker |

Planner does **not** run verify commands or edit source code.

---

## 7. Docker local deployment

### 7.1 Files (to be implemented)

| File | Purpose |
|------|---------|
| `docker-compose.local.yml` | Local VK service definition |
| `.env.agent-ops.example` | Example env for paths, project slug, hcom tag |
| `Makefile` | `up`, `down`, `status`, `validate-dispatch` (Phase 2) |
| `scripts/spawn-agents.sh` | Phase 2: preflight + spawn Cursor + AGY |
| `scripts/validate-dispatch.sh` | Phase 2: check VK issue template fields |

### 7.2 `docker-compose.local.yml` (conceptual)

```yaml
services:
  vibe-kanban:
    build:
      context: .
      dockerfile: Dockerfile
    # Image default user is appuser (uid 10001). Override to host uid:gid so the
    # process can write bind-mounted /repos worktrees. Data/cache use XDG mounts
    # below (not /home/appuser), so they do not depend on image home ownership.
    user: "${VK_UID:-1000}:${VK_GID:-1000}"
    ports:
      # Bind localhost only — VK has no API auth in local mode (see §19)
      - "127.0.0.1:${VK_PORT:-3000}:3000"
    environment:
      XDG_DATA_HOME: /vk-data
      XDG_CACHE_HOME: /vk-cache
      HOST: 0.0.0.0
      PORT: 3000
      VK_ALLOWED_ORIGINS: http://localhost:${VK_PORT:-3000}
    volumes:
      - ${VK_DATA_DIR:-${HOME}/.vk-data}:/vk-data/vibe-kanban
      - ${VK_CACHE_DIR:-${HOME}/.vk-cache}:/vk-cache:rw
      - ${VK_REPOS_DIR:-${HOME}/workspaces}:/repos:rw
    # No healthcheck block — Dockerfile runtime stage already defines one.
    restart: unless-stopped
```

**Env-file caveat:** Compose reads `--env-file` values literally and does **not**
shell-expand `${HOME}`. Leave `VK_DATA_DIR` / `VK_CACHE_DIR` / `VK_REPOS_DIR` unset so the compose
defaults above expand correctly, or set them to absolute paths.

**XDG mounts:** VK stores data under `ProjectDirs` (`XDG_DATA_HOME/vibe-kanban`) and cache under `XDG_CACHE_HOME` (see `crates/utils`). Mounting host dirs at `/vk-data/vibe-kanban` and `/vk-cache` avoids permission issues with the image's `/home/appuser` (uid 10001) when running as host uid via `user:`.

### 7.3 Volume mapping

| Host path | Container path | Contents |
|-----------|----------------|----------|
| `~/.vk-data` | `/vk-data/vibe-kanban` (`XDG_DATA_HOME`) | `db.v2.sqlite`, `config.json`, credentials |
| `~/.vk-cache` | `/vk-cache` (`XDG_CACHE_HOME`) | Attachment cache, temp files |
| `$VK_REPOS_DIR` (default `~/workspaces`) | `/repos` | Git repositories |

**Blast-radius option:** set `VK_REPO_MOUNT` to a single repo path instead of the whole workspaces parent, e.g. `VK_REPO_MOUNT=~/workspaces/myapp` → mount only that directory at `/repos/myapp`.

### 7.4 First-time VK project setup

1. Run `make up` and open `http://localhost:3000`.
2. Add project with container path: `/repos/<repo-name>`.
3. Host agents work in `~/workspaces/<repo-name>` — same files via bind mount.
4. Do **not** use host absolute paths in VK when running Docker VK.

### 7.5 Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VK_PORT` | `3000` | Host port for VK UI/API |
| `VK_DATA_DIR` | `~/.vk-data` | Persistent VK data on host (absolute path only — see §7.2 caveat) |
| `VK_CACHE_DIR` | `~/.vk-cache` | VK cache on host (absolute path only) |
| `VK_REPOS_DIR` | `~/workspaces` | Parent directory of git repos (absolute path only) |
| `VK_UID` / `VK_GID` | `1000` | Host uid:gid the container runs as, so it can write the bind mounts (`id -u`, `id -g`) |
| `MCP_HOST` | `127.0.0.1` | MCP connection host (agents on host) |
| `MCP_PORT` | `3000` | Same as `VK_PORT` |
| `HCOM_TAG` | project slug | hcom room name, e.g. `myapp` |
| `AGY_MODEL` | `gemini-3.7-flash-low` | Default AGY model for verify spawn; run `agy models` and pick newest `gemini-3.7-flash-*` |
| `AGY_MODEL_FALLBACK` | `gemini-3.6-flash-low` | Used if primary model fails at spawn |
| `VK_REPO_MOUNT` | (empty = full `VK_REPOS_DIR`) | Optional single-repo mount to reduce container blast radius |
| `AGENT_ACK_TIMEOUT_MIN` | `30` | Minutes before no-ACK is treated as failure |

---

## 8. Agent connection — MCP

All three agents connect to VK via MCP. Connection from host to Docker VK on `localhost:3000`.

### 8.1 MCP modes

| Mode | Flag | Use when |
|------|------|----------|
| `global` | `--mode global` | Creating/listing issues, proposals, outside workspace |
| `orchestrator` | `--mode orchestrator` | Agent running inside a VK workspace session |

VK auto-injects orchestrator MCP for workspace agents launched **inside VK**. Host-side agents use the static snippet below.

**Clarification:** `agent-ops/mcp/vibe-kanban.json` is for **host-level** agents only (`--mode global`). Do not manually add orchestrator mode to Cursor/Claude/AGY host config — when an agent runs inside a VK workspace session, VK overrides/injects orchestrator MCP automatically. No dual configuration needed.

### 8.2 Shared MCP config snippet (host agents only)

Path: `agent-ops/mcp/vibe-kanban.json`

```json
{
  "vibe-kanban": {
    "command": "npx",
    "args": ["-y", "vibe-kanban", "mcp", "--mode", "global"],
    "env": {
      "MCP_HOST": "127.0.0.1",
      "MCP_PORT": "3000"
    }
  }
}
```

### 8.3 Token-saving MCP rules

1. Call `get_context` **once** at the start of a task, not every turn.
2. Do not `list_*` entire projects when issue ID is known.
3. AGY verifier: read issue by ID + run verify commands; no exploratory listing.
4. Write issue updates in one MCP call when possible.
5. Prefer VK issue body for spec detail; hcom packet links to issue ID only.

---

## 9. Role vs purpose

Two orthogonal fields in every dispatch (Polly-inspired):

| Field | Values | Meaning |
|-------|--------|---------|
| **`role`** | `planner` \| `worker` \| `verifier` \| `reviewer` | Behaviour checklist (`agent-ops/capabilities/<role>.md`) |
| **`purpose`** | `implement` \| `review` \| `explore` \| `verify` \| `search` | Type of work |

Examples:

| Scenario | role | purpose | Typical assignee |
|----------|------|---------|------------------|
| Write code | worker | implement | Cursor or AGY |
| Run tests / lint gate | verifier | verify | AGY |
| Judge a diff | reviewer | review | Claude or different vendor |
| Read-only investigation | worker | explore | AGY or Cursor |
| Find occurrences in codebase | worker | search | AGY (`flash-low`) |

---

## 10. hcom coordination

### 10.1 Room naming

- One hcom tag per VK project: `HCOM_TAG=<project-slug>`
- Agent names: `<tag>-<name>`, e.g. `myapp-claude`, `myapp-cursor`, `myapp-agy`
- Never spawn without a tag.

### 10.2 Message types

| Type | Purpose | Example prefix |
|------|---------|----------------|
| `TASK` | Dispatch work | `[TASK-042]` |
| `VERIFY` | Request verification | `[VERIFY-042]` |
| `ACK` | Completion notice | `--intent ack --` |
| `INFORM` | PASS/FAIL, status | `--intent inform --` |
| `NOTIFY` | New PROPOSAL/DECISION on VK | `[NOTIFY] issue:VK-150` |
| `DISCUSS` | Time-boxed debate | `[DISCUSS] issue:VK-142` |

### 10.3 Task packet format (required fields)

```text
[TASK-042]
issue: VK-142
purpose: implement
role: worker
assign: @myapp-agy
created_by: @myapp-cursor
implementer_vendor: cursor

## Context
(2–5 sentences max — detail lives on VK issue)

## Files
- src/foo.ts

## Steps
1. ...
2. ...

## Acceptance
- [ ] cargo test foo passes

## Verify
command: cargo test foo && cargo clippy -p server
verifier: @myapp-agy
cross_vendor: true
on_fail: reply with file:line + log excerpt; do not redesign
```

### 10.4 VERIFY packet format

```text
[VERIFY-042]
issue: VK-142
purpose: verify
role: verifier
assign: @myapp-agy
implementer: @myapp-cursor
cross_vendor: required

## Commands
cargo test foo && cargo clippy -p server

## On PASS
--intent inform -- PASS VK-142

## On FAIL
--intent inform -- FAIL VK-142
log: <excerpt>
file: src/foo.ts:42
```

### 10.5 DISCUSS format

```text
[DISCUSS] issue:VK-142
topic: Redis vs in-memory cache?
positions:
  @myapp-cursor: Redis — future scale
  @myapp-agy: in-memory — YAGNI
need: @myapp-claude adjudicate
timebox: 1 round
```

**Rules:**

- DISCUSS requires a linked VK issue ID (usually `[DECISION]` or `[BLOCKED]`).
- Facilitator (usually Claude or the user) must post conclusion to VK after DISCUSS.
- Maximum one DISCUSS round before escalating to the user if still unresolved.

---

## 11. Vibe Kanban issue types

Use **title prefix** and **labels** (no custom VK features required).

| Type | Title prefix | Purpose |
|------|--------------|---------|
| TASK | `[TASK]` | Executable work |
| PROPOSAL | `[PROPOSAL]` | Idea or epic needing approval (plan gate) |
| DECISION | `[DECISION]` | Technical choice needing review |
| BLOCKED | `[BLOCKED]` | Stuck; awaiting escalation |

### 11.1 Issue description template

Path: `agent-ops/templates/issue.md`

```markdown
## Type
TASK | PROPOSAL | DECISION | BLOCKED

## Role assignment
assign: @myapp-<agent>
role: worker | planner | verifier | reviewer
purpose: implement | review | explore | verify | search
created_by: @myapp-<agent>
implementer_vendor: claude | cursor | agy

## Context
...

## Acceptance
- [ ] ...

## Verify
command: <shell command>
cross_vendor: true | false

## Reviewers
@myapp-claude

## Escalation
fallback: hcom DISCUSS if no resolution in 2 VK comment rounds
```

### 11.2 Validate-dispatch required fields

`make validate-dispatch` (Phase 2) checks a `[TASK]` issue contains:

- `assign`, `role`, `purpose`, `created_by`
- `implementer_vendor` (for `purpose: implement`)
- `cross_vendor: true | false` and if `false`, a comment explaining exception
- `## Acceptance` with at least one checkbox
- `## Verify` with `command:` (for `purpose: implement` or `verify`)
- `issue:` link if dispatch references a parent PROPOSAL

---

## 12. Workflows

### 12.1 End-to-end diagram

```
┌─ PLAN GATE (epic / >3 tasks)
│   VK [PROPOSAL] → human or Claude APPROVE
│
├─ DISPATCH (act same turn)
│   VK issue + hcom packet (purpose, role, assign)
│
├─ EXECUTE
│   Worker: MCP get_context once → work → hcom ACK
│
├─ VERIFY (cross-vendor when possible)
│   purpose: verify → assign different vendor
│
├─ REVIEW (PROPOSAL / DECISION)
│   purpose: review → VK comments APPROVE / REJECT
│
└─ ESCALATE
    2 VK rounds stuck → [BLOCKED] → hcom DISCUSS → conclusion on VK
```

### 12.2 Normal task flow

```
1. Any agent or user creates [TASK] on VK (MCP)
2. validate-dispatch (optional Phase 2 gate)
3. Creator sends hcom TASK packet → assignee (same turn as step 1)
4. Assignee: MCP get_context once → work → hcom ACK
5. Dispatcher sends [VERIFY] → verifier (cross-vendor if possible)
6. Verifier: run verify command → INFORM PASS/FAIL
7. PASS → update VK status done
   FAIL (< 2) → re-dispatch to worker with error log
   FAIL (≥ 2) → create [DECISION] or assign Claude reviewer
```

### 12.3 Proposal flow (plan gate)

```
1. Any agent creates [PROPOSAL] on VK (required before >3 task fan-out)
1b. On APPROVE: planner (role: planner) creates child [TASK] issues + hcom packets
2. hcom NOTIFY → reviewers (typically @myapp-claude)
3. Review on VK comments: APPROVE | REJECT | NEEDS_INFO
4. APPROVE → create child [TASK] issues or convert issue
5. REJECT → close with reason
6. NEEDS_INFO → assign back to proposer
7. If 2 VK rounds without resolution → [BLOCKED] + hcom DISCUSS
```

### 12.4 Decision flow

```
1. Any agent creates [DECISION] on VK (or TASK fails ≥ 2 times)
2. Assign reviewer(s) in issue body
3. Review on VK: comment with decision + rationale
4. Record outcome in issue; unblock related TASK
5. If 2 VK rounds without resolution → [BLOCKED] + hcom DISCUSS
```

### 12.5 Flexible assignment example

Cursor creates and assigns to AGY:

```
1. @myapp-cursor: MCP create [TASK] VK-160 (same turn → hcom send)
2. @myapp-cursor: hcom send @myapp-agy --
     [TASK-160] purpose:implement role:worker assign:@myapp-agy ...
3. @myapp-agy: implement → ACK
4. @myapp-cursor: hcom send @myapp-claude --
     [VERIFY-160] purpose:verify role:reviewer cross_vendor:true ...
```

### 12.6 Agent suggestion → ticket flow

```
1. Any agent has an idea → MCP create [PROPOSAL] or [DECISION] on VK
2. hcom NOTIFY reviewers
3. Review on VK (single or multi-reviewer)
4. APPROVE → spawn [TASK] with hcom dispatch
5. Cannot resolve on VK → [BLOCKED] → hcom DISCUSS → record conclusion on VK
```

### 12.7 Communication channel matrix

| Content | Primary channel | Secondary |
|---------|-----------------|-----------|
| Task state (todo/doing/done) | VK | — |
| Spec + acceptance | VK issue body | — |
| Dispatch (who does what) | hcom TASK packet | VK Role assignment block |
| Ideas / suggestions | VK PROPOSAL | hcom NOTIFY |
| Review / approve | VK comments | — |
| Technical disagreement | VK DECISION comments | hcom DISCUSS if stuck |
| Done / PASS-FAIL | hcom ACK/INFORM | VK status update |

---

## 13. When to use hcom DISCUSS

### Use DISCUSS when

- PROPOSAL or DECISION has **2 VK comment rounds** without resolution
- Verify **FAIL ≥ 2** and root cause is ambiguous
- Acceptance criteria are contradictory
- Cross-cutting architectural impact
- Agents disagree on approach after VK comments

### Do not use DISCUSS when

- Routine task completion → hcom ACK only
- Mechanical PASS/FAIL → INFORM only
- Single clarification → VK comment
- Brainstorming without an issue → create PROPOSAL on VK first
- Plan not yet approved → wait for PROPOSAL APPROVE (plan gate)

---

## 14. agent-ops directory structure

```
agent-ops/
├── base.md                    # VK + hcom + orchestration principles (§6)
├── capabilities/
│   ├── planner.md             # role=planner
│   ├── worker.md              # role=worker
│   ├── verifier.md            # role=verifier
│   ├── reviewer.md            # role=reviewer
│   └── explore.md             # purpose=explore|search
├── templates/
│   └── issue.md               # VK issue template
├── mcp/
│   └── vibe-kanban.json       # MCP config snippet
└── hcom/
    └── message-formats.md     # TASK, VERIFY, DISCUSS examples
```

### 14.1 Injection per agent

| Agent | Injection method |
|-------|------------------|
| **Cursor** | `.cursor/rules/agent-ops.mdc` references `agent-ops/base.md` |
| **Claude** | Skill or project `CLAUDE.md` points to `agent-ops/` |
| **AGY** | `hcom agy --hcom-system-prompt "$(cat agent-ops/base.md)"` at spawn |

Capability file = `role` from packet. For `purpose: explore|search`, also read `capabilities/explore.md`.

### 14.2 base.md core rules (summary)

1. VK is the source of truth for all tasks and decisions.
2. `role` and `purpose` are per-task in the packet; agent type is not a fixed role.
3. Any agent with MCP may create PROPOSAL, DECISION, or TASK issues.
4. Act same turn: VK write + hcom send together.
5. No busy-poll: wait for hcom delivery when idle.
6. Cross-vendor verify/review when roster allows.
7. hcom DISCUSS only when VK cannot resolve in 2 comment rounds.
8. After DISCUSS, post conclusion to VK (mandatory).
9. Plan gate: PROPOSAL approval before >3 task fan-out.
10. Keep hcom messages short; put detail in VK issues.
11. Translate MCP container paths to host paths before file operations (§6.8).

---

## 15. Bootstrap — phased Makefile

### Phase 1 (implement first)

| Target | Action |
|--------|--------|
| `make up` | `docker compose -f docker-compose.local.yml up -d --build` |
| `make down` | `docker compose -f docker-compose.local.yml down` |
| `make status` | VK health check + `uvx hcom list` |
| `make logs` | `docker compose -f docker-compose.local.yml logs -f` |

### Phase 2 (after workflow validated)

| Target | Action |
|--------|--------|
| `make agents-up` | `scripts/spawn-agents.sh` (preflight + spawn) |
| `make agents-down` | Document `hcom stop tag:<slug>` (user-initiated only) |
| `make mcp-install` | Print/merge MCP config for each agent |
| `make validate-dispatch` | `scripts/validate-dispatch.sh ISSUE=...` |
| `make reset-room` | NOTIFY room; do not kill agents without user consent |

### 15.1 Roster preflight (Polly-inspired)

`scripts/spawn-agents.sh` runs before spawn (spawned agents only — not Claude):

```bash
command -v cursor-agent agy || true
# Report missing binaries; continue with available agents only
```

Claude uses the user's existing session — not spawned by this script. Optional separate check: `command -v claude` printed as info only.

If a worker is missing, do not dispatch to it for the session; note in hcom NOTIFY. Update VK issue field `cross_vendor_met: exception:<reason>` when cross-vendor rule cannot be satisfied.

### 15.2 Spawn commands

Reads `.env.agent-ops`:

```env
HCOM_TAG=myapp
VK_PORT=3000
AGY_MODEL=gemini-3.7-flash-low
```

```bash
HCOM_TAG=$HCOM_TAG uvx hcom cursor
HCOM_TAG=$HCOM_TAG uvx hcom agy --model $AGY_MODEL \
  --hcom-system-prompt "$(cat agent-ops/base.md)"
```

Claude: user's existing session + `uvx hcom start --as ${HCOM_TAG}-claude`.

**No second Claude planner spawn** — the user's Claude session is the default planner/adjudicator.

---

## 16. Multi-repo extension (designed, not Phase 1)

| Concept | Convention |
|---------|------------|
| VK instance | Single Docker VK, shared `~/.vk-data` |
| Repos | All under `VK_REPOS_DIR`, each added as `/repos/<name>` |
| hcom room | One tag per project slug |
| `.env.agent-ops` | Per-repo copy or symlink with different `HCOM_TAG` |

---

## 17. Token cost guidelines

| Layer | Practice |
|-------|----------|
| Planning | Batch issues; use issue template; plan gate avoids wasted fan-out |
| MCP | `get_context` once per task |
| Worker | Detailed spec in VK → less exploration |
| Verifier | AGY `gemini-3.7-flash-low`; run commands only |
| Explorer | AGY `gemini-3.7-flash-low` for search/explore |
| hcom | ACK/INFORM short; DISCUSS only when stuck |
| Debate | Kanban first; hcom is expensive fallback |
| Idle | No poll — zero token cost while waiting |

---

## 18. Error handling

| Situation | Action |
|-----------|--------|
| VK health check fails | `make logs`; verify port and volumes |
| MCP cannot connect | Check `MCP_HOST=127.0.0.1`, `MCP_PORT` matches `VK_PORT` |
| Agent blocked on approval | `hcom list --json` → match cwd → focus pane in herdr |
| Repo path mismatch | VK project must use `/repos/...` not host path; use §6.8 path mapping on host |
| DISCUSS without VK issue | Reject; create DECISION issue first |
| FAIL ≥ 2 on verify | Create DECISION or escalate to Claude reviewer |
| Missing agent in roster | NOTIFY room; reassign to available agent |
| validate-dispatch fails | Fix issue template before hcom send |
| **SQLite lock / slow I/O on WSL2** | VK uses `SqliteJournalMode::Delete` (more fsync-sensitive than WAL). Keep `VK_DATA_DIR` on Linux fs in WSL (`~/.vk-data`, not `/mnt/c/...`); run `make status` after heavy write; backup `db.v2.sqlite` if corruption suspected |
| **Container cannot write worktrees** | uid mismatch on `/repos`: set `VK_UID`/`VK_GID` to `id -u`/`id -g` (§7.2). Image default user is 10001; bind mounts are host-owned |
| **Container cannot write DB / cache** | Check `XDG_DATA_HOME` / `XDG_CACHE_HOME` mounts and host dir ownership (`make logs`) |
| **No ACK past timeout** | See §6.7; NOTIFY + reassign |
| **AGY model invalid** | Fall back to `AGY_MODEL_FALLBACK`; run `agy models` |

---

## 19. Security notes

- Do not commit `.env.agent-ops` with secrets.
- `VK_ALLOWED_ORIGINS` must include the browser origin used to access VK.
- **Local VK has no API authentication** — security boundary is `127.0.0.1` port bind (§7.2). Do not expose port `0.0.0.0` on untrusted networks. Full auth is out of scope for Phase 1 (local dev only).
- hcom: do not `kill` agents without explicit user request.
- Bind mounts give the container read/write access to mounted repos; prefer `VK_REPO_MOUNT` for single-repo scope when possible.

---

## 20. Implementation plan (next step)

After this spec is approved, invoke **writing-plans** to produce:

1. `docker-compose.local.yml` + `.env.agent-ops.example`
2. `Makefile` Phase 1 + Phase 2 targets
3. `agent-ops/` content files (base, capabilities including `explore.md`, templates, hcom formats)
4. `.cursor/rules/agent-ops.mdc`
5. `scripts/spawn-agents.sh` with roster preflight
6. `scripts/validate-dispatch.sh`

**Out of scope for initial implementation:**

- Automated VK project creation via API
- Custom VK issue types beyond title prefix/labels
- AGY MCP auto-install if AGY lacks MCP support (document manual fallback)
- Optional Polly-style PR-per-subtask automation

---

## 21. Open decisions (resolved)

| Question | Decision |
|----------|----------|
| Docker scope | VK server only; agents on host |
| Data persistence | `~/.vk-data` + `~/workspaces` bind mounts |
| Task source of truth | VK |
| hcom role | Inbox-style dispatch, notify, DISCUSS fallback |
| MCP on all agents | Yes |
| Fixed roles per agent | No — per-task `role` + `purpose` in packet |
| Cross-vendor review | Preferred when roster allows |
| Bootstrap approach | Phased Makefile |
| Multi-repo | Design for extension; start with one repo |
| CAO/Omnigent integration | Patterns only, not full server stack |

---

## 22. Open risks (accepted for Phase 1)

| Risk | Mitigation |
|------|------------|
| hcom hook delivery may differ across Claude / Cursor / AGY | Validate in Phase 2 smoke test; fall back to NOTIFY + human nudge |
| Cross-vendor rule soft when agent offline | Require `cross_vendor_met` field on VERIFY close |
| MCP concurrent writes | Agents use VK HTTP API (not raw SQLite); server serializes writes — monitor WSL2 I/O separately |
| VK sunsetting | Spec is self-hosted local; no cloud dependency |

---

## 23. Review log — @agent-ops-kona (2026-08-15)

**Verdict:** REVISE → patches applied by @agent-ops-cursor

| # | Finding | Resolution |
|---|---------|------------|
| 1 | Path translation host↔container | **Accepted** — §6.8 + base.md rule #11 |
| 2 | `role: planner` unused | **Accepted** — §6.9 + §12.3 step 1b |
| 3 | No timeout handling | **Accepted** — §6.7 + `AGENT_ACK_TIMEOUT_MIN` |
| 4 | validate-dispatch incomplete | **Accepted** — §11.2 expanded |
| 5 | SQLite concurrent access | **Debated** — agents use API not SQLite; WSL2 note in §18 |
| 6 | No VK API auth | **Accepted** — localhost bind + §19 explicit out-of-scope |
| 7 | MCP global vs orchestrator ambiguity | **Accepted** — §8.1–8.2 clarification |
| 8 | Preflight checks `claude` incorrectly | **Accepted** — §15.1 fixed |
| 9 | Port exposes LAN | **Accepted** — `127.0.0.1:` bind |
| 10 | WSL2 SQLite bind-mount | **Accepted** — §18 row |
| 11 | Full `~/workspaces` blast radius | **Accepted** — `VK_REPO_MOUNT` option |
| 12 | Cross-vendor soft enforcement | **Accepted** — `cross_vendor_met` field |
| 13 | hcom hook parity unverified | **Accepted** — §22 open risk |
| 14 | AGY model name uncertainty | **Accepted** — `AGY_MODEL_FALLBACK` |

**Pending debate (hcom DISCUSS):** ~~whether 30 min ACK timeout is too long~~ **Resolved** — 30 min OK as human heuristic; ~~path-map.sh~~ **Removed** (YAGNI).

**Final verdict:** **APPROVE** — ready for `writing-plans`.

---

## 24. Spec self-review

- [x] CAO and Polly patterns mapped with explicit adopt/reject list
- [x] `purpose` field defined alongside `role`
- [x] Cross-vendor, act-same-turn, no-poll, plan gate, validate-dispatch documented
- [x] Roster preflight in spawn script (cursor + agy only)
- [x] Path mapping §6.8 documented
- [x] Kona REVISE items addressed or debated in §23
- [x] No TBD placeholders in workflow or file paths
- [x] Architecture consistent with VK Docker + host agents
- [x] Kanban-first and hcom-fallback rules are explicit and non-contradictory
- [x] Scope bounded to Phase 1 + documented Phase 2
- [x] AGY model defaults + fallback documented
