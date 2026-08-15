# Agent Ops Local

Local Vibe Kanban in Docker + hcom multi-agent coordination.

## Quick start

1. `cp .env.agent-ops.example .env.agent-ops` — set `VK_UID`/`VK_GID` to `id -u` / `id -g`
2. `make up` — build and start VK at http://localhost:3000 (creates `~/.vk-data` and `~/.vk-cache`)
3. Add VK project with container path `/repos/<your-repo>` (host: `~/workspaces/<your-repo>`)
4. Merge `agent-ops/mcp/vibe-kanban.json` into Cursor/Claude MCP config
5. `HCOM_TAG=myapp uvx hcom cursor` and `uvx hcom start --as myapp-claude` for Claude
6. `make status` — VK health + hcom list

## WSL2

Keep `VK_DATA_DIR` on Linux filesystem (`~/.vk-data`), not `/mnt/c/...`. VK uses SQLite with `Delete` journal mode — slow cross-filesystem mounts cause I/O issues.

## Optional single-repo mount

Set `VK_REPO_MOUNT` in `.env.agent-ops` and replace the repos volume line in `docker-compose.local.yml` to reduce blast radius.

## Verification

```bash
cp .env.agent-ops.example .env.agent-ops   # set VK_UID/VK_GID
bash scripts/tests/validate-dispatch.test.sh
docker compose -f docker-compose.local.yml config --quiet
make up && make status && make down
```

After `make up`, confirm DB created:

```bash
ls ~/.vk-data/db.v2.sqlite
```

If missing, check `VK_UID`/`VK_GID` match mount directory owner (`make logs`).

## Commands

| Command | Description |
|---------|-------------|
| `make up` | Start VK Docker |
| `make down` | Stop VK Docker |
| `make status` | Health + hcom list |
| `make agents-up` | Spawn Cursor + AGY (Phase 2) |
| `make validate-dispatch ISSUE=path` | Validate issue template |
| `make mcp-install` | Print MCP config snippet |

## Docs

- Spec: `docs/superpowers/specs/2026-08-15-agent-ops-local-design.md`
- Plan: `docs/superpowers/plans/2026-08-15-agent-ops-local.md`
- Rules: `agent-ops/base.md`
