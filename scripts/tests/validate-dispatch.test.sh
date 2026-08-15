#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATOR="$ROOT/scripts/validate-dispatch.sh"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

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
