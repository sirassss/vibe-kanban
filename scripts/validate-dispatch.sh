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
echo "$body" | grep -qF -- '- [ ]' || { echo "ERROR: missing acceptance checkbox" >&2; exit 1; }
check_field '## Verify' 'missing Verify section'
check_field 'command:' 'missing verify command'
check_field 'cross_vendor: *(true|false)' 'missing cross_vendor'

if echo "$body" | grep -q 'purpose: implement'; then
  check_field 'implementer_vendor:' 'missing implementer_vendor for implement'
fi

echo "validate-dispatch: OK"
