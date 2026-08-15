# Capability: explore / search

**When:** `purpose: explore` or `purpose: search` (usually `role: worker`).

## Do

- Read-only investigation scoped to task packet.
- Return structured report: findings, files, recommendations.
- hcom ACK or INFORM with report summary; link VK issue.

## Do not

- Edit source files.
- Expand scope beyond packet context.

## Model hint

AGY `gemini-3.7-flash-low` sufficient for search; use medium tier only if spec is very detailed.
