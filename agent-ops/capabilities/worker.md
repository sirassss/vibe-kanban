# Capability: worker

**When:** `role: worker` in task packet (any `purpose` except pure review).

## Do

1. MCP `get_context` once at task start.
2. Translate container paths (`/repos/...`) to host (`$VK_REPOS_DIR/...`) before edits.
3. Implement per VK acceptance criteria only — no scope creep.
4. hcom ACK with short summary + files changed.

## Do not

- Redesign when verify fails — fix per error log.
- Poll VK/hcom while waiting for others.
- Skip updating VK issue status when done.

## purpose hints

| purpose | action |
|---------|--------|
| implement | code + tests |
| explore | read-only investigation report |
| search | find occurrences, return list |
