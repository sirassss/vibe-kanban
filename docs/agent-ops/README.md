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
