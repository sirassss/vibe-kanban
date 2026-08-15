COMPOSE_FILE := docker-compose.local.yml
ENV_FILE := .env.agent-ops
VK_PORT ?= 3000

.PHONY: up down status logs agents-up agents-down mcp-install validate-dispatch

up:
	@mkdir -p "$${VK_DATA_DIR:-$$HOME/.vk-data}" "$${VK_CACHE_DIR:-$$HOME/.vk-cache}" "$${VK_REPOS_DIR:-$$HOME/workspaces}"
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) up -d --build

down:
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) down

status:
	@curl -sf "http://127.0.0.1:$(VK_PORT)/health" && echo " VK health: OK" || echo " VK health: FAIL"
	@uvx hcom list 2>/dev/null || echo "hcom: not available"

logs:
	docker compose -f $(COMPOSE_FILE) --env-file $(ENV_FILE) logs -f

agents-up:
	@test -f scripts/spawn-agents.sh || (echo "run after Task 9" && exit 1)
	@bash scripts/spawn-agents.sh

agents-down:
	@echo "Run manually: uvx hcom stop tag:<HCOM_TAG>  (user-initiated only)"

mcp-install:
	@echo "=== Cursor / Claude: merge agent-ops/mcp/vibe-kanban.json into your MCP config ==="
	@cat agent-ops/mcp/vibe-kanban.json

validate-dispatch:
	@test -n "$(ISSUE)" || (echo "Usage: make validate-dispatch ISSUE=path/to/issue.md" && exit 1)
	@bash scripts/validate-dispatch.sh "$(ISSUE)"
