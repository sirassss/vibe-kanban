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
