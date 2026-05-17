.PHONY: help run git-auth-check build up down restart logs ps test typecheck typecheck-staged install-hooks check-tools check-env init

SERVICE := sentinel-listener

help:
	@echo "Targets:"
	@echo "  make run       - start Docker listener and show startup logs"
	@echo "  make build     - build Docker image"
	@echo "  make up        - start listener container"
	@echo "  make down      - stop listener container"
	@echo "  make restart   - restart listener container"
	@echo "  make logs      - follow listener logs"
	@echo "  make ps        - show container status"
	@echo "  make typecheck - run type checks for all tracked files"
	@echo "  make typecheck-staged - run type checks for staged files"
	@echo "  make install-hooks - enable repository pre-commit hook"
	@echo "  make test      - run local shell tests"
	@echo "  make init      - scaffold config and prompts for repos in TARGET_REPOS"

check-tools:
	@command -v docker >/dev/null 2>&1 || (echo "docker is required" && exit 1)
	@docker compose version >/dev/null 2>&1 || (echo "docker compose is required" && exit 1)

check-env:
	@test -f .env || (echo ".env not found. Copy .env.example to .env first." && exit 1)
	@grep -Eq '^GH_TOKEN=.+' .env || (echo "GH_TOKEN is missing in .env" && exit 1)
	@grep -Eq '^ANTHROPIC_API_KEY=.+' .env || (echo "ANTHROPIC_API_KEY is missing in .env" && exit 1)
	@grep -Eq '^MY_GITHUB_USERNAME=.+' .env || (echo "MY_GITHUB_USERNAME is missing in .env" && exit 1)
	@grep -Eq '^TARGET_REPOS=.+' .env || (echo "TARGET_REPOS is missing in .env" && exit 1)

build: check-tools check-env
	docker compose build $(SERVICE)

up: check-tools check-env
	docker compose up -d $(SERVICE)

run: check-tools check-env
	docker compose up -d --build $(SERVICE)
	@echo "Listener started. Recent logs:"
	@docker compose logs --tail=20 $(SERVICE)
	@echo "Use 'make logs' to follow continuously."

git-auth-check:
	@command -v gh >/dev/null 2>&1 || (echo "gh CLI is required" && exit 1)
	@GH_PAGER=cat gh auth status >/dev/null 2>&1 || (echo "gh auth not ready. Run 'gh auth login'." && exit 1)
	@echo "gh auth is ready"

down: check-tools
	docker compose down

restart: down run

logs: check-tools
	docker compose logs -f $(SERVICE)

ps: check-tools
	docker compose ps

test:
	@for f in commands/*.sh workflows/*.sh services/github/*.sh services/ai/*.sh services/git/*.sh utils/*.sh tests/*.sh; do bash -n "$$f" || exit 1; done
	@for f in tests/test-*.sh; do \
	  PATH="$(CURDIR)/tests/stubs:$$PATH" ANTHROPIC_API_KEY="" bash "$$f" || exit 1; \
	done

typecheck:
	@bash utils/typecheck.sh all

typecheck-staged:
	@bash utils/typecheck.sh staged

install-hooks:
	@test -f .githooks/pre-commit || (echo ".githooks/pre-commit not found" && exit 1)
	@chmod +x .githooks/pre-commit utils/typecheck.sh
	@git config core.hooksPath .githooks
	@echo "Git hooks enabled via core.hooksPath=.githooks"

init: check-env
	@set -a && . ./.env && set +a && bash commands/init.sh
