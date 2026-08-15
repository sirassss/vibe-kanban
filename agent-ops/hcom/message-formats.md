# hcom Message Formats

## TASK packet

```text
[TASK-042]
issue: VK-142
purpose: implement
role: worker
assign: @myapp-agy
created_by: @myapp-cursor
implementer_vendor: cursor

## Context
(2–5 sentences — detail on VK issue)

## Files
- src/foo.ts

## Steps
1. ...

## Acceptance
- [ ] cargo test foo passes

## Verify
command: cargo test foo && cargo clippy -p server
verifier: @myapp-agy
cross_vendor: true
on_fail: reply with file:line + log excerpt; do not redesign
```

## VERIFY packet

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

## NOTIFY

```text
[NOTIFY] issue:VK-150
type: PROPOSAL
reviewers: @myapp-claude
```

## DISCUSS

```text
[DISCUSS] issue:VK-142
topic: Redis vs in-memory cache?
positions:
  @myapp-cursor: Redis — future scale
  @myapp-agy: in-memory — YAGNI
need: @myapp-claude adjudicate
timebox: 1 round
```

Rules: DISCUSS requires VK issue ID. Post conclusion to VK after DISCUSS.
