# Shortcuts for local work. CI calls ./gradlew and npm directly, so each step stays visible in the Actions logs.
# Commands reference: docs/documentation-technique.md, section 2.2.

.PHONY: help build test test-back test-front up down logs ps smoke

help: ## List the available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  make %-11s %s\n", $$1, $$2}'

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
