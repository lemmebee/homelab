DC := docker compose

.PHONY: up down restart ps logs rollout build pull clean

up:            ## Start proxy + all apps
	$(DC) up -d

down:          ## Stop everything
	$(DC) down

restart:       ## Restart everything
	$(DC) restart

ps:            ## Show status
	$(DC) ps

logs:          ## Tail logs. app=<name> for one app, else all
	$(DC) logs -f $(app)

rollout:       ## Rebuild + restart one app: make rollout app=ouioui
	@test -n "$(app)" || (echo "usage: make rollout app=<name>"; exit 1)
	$(DC) up -d --build --force-recreate $(app)

build:         ## Rebuild image(s) without starting. app=<name> optional
	$(DC) build $(app)

clean:         ## Stop and remove volumes (DESTROYS app data)
	$(DC) down -v

help:
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/'
