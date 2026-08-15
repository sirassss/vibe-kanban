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
