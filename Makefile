.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help up down reset logs logs-sql migrate psql loadtest-1 loadtest-2 measure-1 measure-2 test

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack (first run seeds ~1.8M rows, takes 2-4 minutes)
	$(COMPOSE) up -d --build
	@echo ""
	@echo "Waiting for the backend to become healthy..."
	@for i in $$(seq 1 90); do \
		if curl -fsS http://localhost:8080/actuator/health >/dev/null 2>&1; then \
			echo "Backend is up."; break; \
		fi; \
		sleep 3; \
	done
	@echo ""
	@echo "  UI        http://localhost:5173"
	@echo "  API       http://localhost:8080/api/orders?limit=50"
	@echo "  Postgres  localhost:5432  (db: scaledemo, user: demo, password: demo)"
	@echo ""
	@echo "Next: open docs/00-setup.md"

down: ## Stop the stack, keep the seeded database volume
	$(COMPOSE) down

reset: ## Full reset: drop the database volume and discard Copilot's edits
	$(COMPOSE) down -v
	@echo ""
	@echo "Database volume removed."
	@echo "To also discard code changes Copilot made during the demo, run:"
	@echo "    git checkout -- . && git clean -fd db/migrations"

logs: ## Tail backend logs
	$(COMPOSE) logs -f backend

logs-sql: ## Tail only the SQL Hibernate emits (this is where N+1 is visible)
	$(COMPOSE) logs -f backend | grep --line-buffered "org.hibernate.SQL"

migrate: ## Apply every .sql file in db/migrations in filename order
	@set -e; \
	shopt -s nullglob 2>/dev/null || true; \
	found=0; \
	for f in db/migrations/*.sql; do \
		found=1; \
		echo "==> applying $$f"; \
		$(COMPOSE) exec -T db psql -v ON_ERROR_STOP=1 -U demo -d scaledemo < "$$f"; \
	done; \
	if [ "$$found" = "0" ]; then echo "No migrations found in db/migrations/."; fi

psql: ## Open a psql shell as the app user
	$(COMPOSE) exec db psql -U demo -d scaledemo

psql-reader: ## Open a psql shell as the read-only Copilot role
	$(COMPOSE) exec db psql -U copilot_perf_reader -d scaledemo

loadtest-1: ## Load test scenario 1 (orders list / N+1)
	$(COMPOSE) run --rm k6 run /scripts/scenario-1-orders.js

loadtest-2: ## Load test scenario 2 (order search / missing index)
	$(COMPOSE) run --rm k6 run /scripts/scenario-2-search.js

measure-1: ## Single request against scenario 1, prints query count and server time
	@curl -s "http://localhost:8080/api/orders?limit=50" \
		| python3 -c "import sys,json;d=json.load(sys.stdin);print('sqlQueryCount=%s  serverMillis=%s  rows=%s'%(d['sqlQueryCount'],d['serverMillis'],len(d['data'])))"

measure-2: ## Single request against scenario 2, prints query count and server time
	@curl -s "http://localhost:8080/api/orders/search?status=SHIPPED&withinHours=48&limit=50" \
		| python3 -c "import sys,json;d=json.load(sys.stdin);print('sqlQueryCount=%s  serverMillis=%s  rows=%s'%(d['sqlQueryCount'],d['serverMillis'],len(d['data'])))"

test: ## Run the backend test suite (includes the query-count regression test)
	docker run --rm \
		-v "$$PWD/backend":/app -w /app \
		-v "$$HOME/.m2":/root/.m2 \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-e TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal \
		maven:3.9-eclipse-temurin-25 mvn -B test
