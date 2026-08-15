# Agent Ops — Base Rules

You operate in the **Vibe Kanban (VK) + hcom** multi-agent stack.

## Source of truth

- **VK** owns task state, specs, acceptance criteria, and decisions.
- **hcom** is dispatch, ack, notify, and time-boxed DISCUSS only — not a task registry.

## Roles (per task, not per agent)

Each task packet defines:

- `role`: `planner` | `worker` | `verifier` | `reviewer` → read `agent-ops/capabilities/<role>.md`
- `purpose`: `implement` | `review` | `explore` | `verify` | `search`

Agent type (Claude/Cursor/AGY) is a capability hint, not a fixed role.

## Orchestration rules

1. **Act same turn** — VK MCP write + hcom send in one turn when dispatching.
2. **No busy-poll** — wait for hcom delivery; do not loop on VK/hcom status when idle.
3. **Path mapping** — MCP may return container paths. Before host file/git ops, translate:
   - `/repos/foo` → `$VK_REPOS_DIR/foo` (default `~/workspaces/foo`)
4. **Cross-vendor** — verifier/reviewer should differ from implementer vendor when roster allows.
   - On VERIFY close, set `cross_vendor_met: true` or `cross_vendor_met: exception:<reason>` on VK issue.
5. **Plan gate** — before fan-out >3 tasks, create `[PROPOSAL]` on VK and get APPROVE.
6. **DISCUSS** — only after 2 VK comment rounds stuck on PROPOSAL/DECISION; post conclusion to VK after.
7. **ACK timeout** — `AGENT_ACK_TIMEOUT_MIN` (default 30) is a **human coordinator heuristic** in Phase 1, not automated.
8. **Keep hcom short** — detail lives in VK issue body; packet links `issue: VK-###`.

## MCP token savings

- Call `get_context` once per task.
- Do not list entire projects when issue ID is known.
- Host agents use `global` MCP mode; VK injects `orchestrator` inside workspace sessions.

## When stuck

- FAIL once → re-dispatch worker with error log.
- FAIL twice → `[DECISION]` or assign Claude reviewer.
- Worker wrong/stuck → fresh dispatch with revised spec; do not vague re-prompt loops.
