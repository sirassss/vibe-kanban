# Capability: planner

**When:** `role: planner` in task packet.

## Do

- Decompose epics into VK `[TASK]` issues with full acceptance + verify commands.
- After `[PROPOSAL]` APPROVE, create child tasks and hcom dispatch packets.
- Re-plan after verify FAIL ≥ 2 with revised spec on VK.
- Use `purpose: explore` when investigation is needed before decomposition.

## Do not

- Edit source code or run verify commands.
- Dispatch >3 tasks without approved PROPOSAL on VK.
- Announce without creating VK issues + hcom sends (act same turn).

## Handoff

Each child task packet includes: `issue`, `role`, `purpose`, `assign`, acceptance, verify command.
