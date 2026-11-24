# Shortcuts for local work. CI calls ./gradlew and npm directly, so each step stays visible in the Actions logs.
# Commands reference: docs/documentation-technique.md, section 2.2.

.PHONY: help build test test-back test-front up down logs ps smoke backup restore elk-up elk-down elk-dashboards traffic

help: ## List the available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  make %-15s %s\n", $$1, $$2}'

build: ## Build both Docker images
	docker compose build

test: test-back test-front ## Run all tests (back + front)

test-back: ## Back-end tests and coverage report (JaCoCo)
	cd back && ./gradlew build jacocoTestReport

test-front: ## Front-end tests with coverage (headless Chrome)
	cd front && npm ci --ignore-scripts && npm test -- --watch=false --browsers=ChromeHeadlessNoSandbox --code-coverage

up: ## Build and start the application (http://localhost:4200, API on :8080)
	docker compose up -d --build

down: ## Stop and remove the containers
	docker compose down

logs: ## Follow the logs of both services
	docker compose logs -f

ps: ## Show the containers and their health
	docker compose ps

smoke: ## Check that the running application answers (API + front)
	curl -fsS -o /dev/null http://localhost:8080/persons && echo "API   OK"
	curl -fsS -o /dev/null http://localhost:4200/ && echo "front OK"

backup: ## Back up the database to backups/ (the API stops for a few seconds)
	@mkdir -p backups
	docker compose stop back
	docker compose run --rm --no-deps --user root -v "$(CURDIR)/backups:/backups" --entrypoint sh back \
		-c 'tar czf /backups/microcrm-$$(date +%Y%m%d-%H%M%S).tar.gz -C /data .'
	docker compose start back
	@ls -1t backups/*.tar.gz | head -1

# Restore only into an EMPTY database: replacing existing data must be a deliberate human action
# (see section 7.3 of the documentation), never a side effect of this command.
restore: ## Restore a backup into an empty database: make restore FILE=backups/microcrm-<date>.tar.gz
	@test -f "$(FILE)" || { echo "Usage: make restore FILE=backups/microcrm-<date>.tar.gz"; exit 1; }
	docker compose stop back
	docker compose run --rm --no-deps --user root -v "$(CURDIR)/backups:/backups" --entrypoint sh back \
		-c '[ -z "$$(ls -A /data)" ] || { echo "Database not empty: see section 7.3"; exit 1; }; tar xzf /backups/$(notdir $(FILE)) -C /data && chown -R app:app /data'
	docker compose up -d back

# ---- Local monitoring (ELK). Not part of CI/CD. Needs .env (copy .env.example) and ~3 GB of free RAM.
elk-up: ## Start the ELK stack (Kibana on http://localhost:5601, user elastic)
	@test -f .env || { echo "Missing .env: cp .env.example .env, then set the passwords"; exit 1; }
	docker compose -f docker-compose-elk.yml up -d --wait

elk-down: ## Stop the ELK stack (the collected logs are kept on the es-data volume)
	docker compose -f docker-compose-elk.yml down

elk-dashboards: ## Create the Kibana data view and the MicroCRM dashboard
	@test -f .env || { echo "Missing .env"; exit 1; }
	./elk/kibana/import-dashboards.sh

traffic: ## Simulate user traffic for the dashboards: make traffic [DURATION=300]
	./scripts/traffic.sh $(or $(DURATION),300)
