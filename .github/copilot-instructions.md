# Copilot instructions: scalability demo

This repository is a teaching demo for diagnosing and fixing web application scalability
problems with GitHub Copilot. It contains deliberately planted performance defects. Do not
"tidy them up" unless the user explicitly asks for a fix.

## Stack

- PostgreSQL 17 (`db/`), extensions: `pg_stat_statements`, `hypopg`
- Spring Boot 3.5 on Java 25, Hibernate 6, HikariCP, virtual threads enabled (`backend/`)
- React 19 + Vite dev server (`frontend/`)
- k6 for load testing (`loadtest/`)
- Everything runs under Docker Compose. There is no cloud dependency.

## Performance ground rules

These are the rules that matter most in this repo. Follow them in every performance answer.

1. **No number, no problem.** Never call something slow, fast, a bottleneck, or "optimized"
   without a measurement. Acceptable evidence is: a k6 percentile, `EXPLAIN (ANALYZE, BUFFERS)`
   output, a row from `pg_stat_statements`, or the `sqlQueryCount` / `serverMillis` fields the
   API returns. A code reading is a hypothesis, not evidence.
2. **Percentiles, not averages.** Report p95 and p99. An average hides the tail that users feel.
3. **Change one thing at a time.** If two changes ship together and latency moves, you have
   learned nothing about which one did it.
4. **Re-measure after every change and state the before and after side by side.** If the number
   did not move, say so plainly rather than describing the change as an improvement.
5. **Prefer the cheapest fix that moves the number.** An index or a fetch strategy beats a cache;
   a cache beats a rewrite; a rewrite beats new infrastructure. Do not propose Redis, a read
   replica, sharding, or a queue before the query plan has been read.
6. **Say when you are guessing.** If you have no access to the database or to load-test output,
   state that the answer is a hypothesis derived from source code and name the measurement that
   would confirm or kill it.

## Service level objectives

These are the targets the load tests and the CI gate enforce.

| Endpoint | p95 latency | SQL statements per request |
| --- | --- | --- |
| `GET /api/orders` | < 150 ms | < 5 |
| `GET /api/orders/search` | < 50 ms server time | 1 |

Do not weaken a threshold to make a test pass. If a threshold is wrong, argue for a new number
with data and change it deliberately.

## Measurement tools available in this repo

- `make loadtest-1` / `make loadtest-2` run k6 and print p95 plus custom metrics.
- `make measure-1` / `make measure-2` issue a single request and print `sqlQueryCount` and
  `serverMillis`.
- `make logs-sql` tails only Hibernate's SQL output, which is where query amplification shows up.
- `make psql` opens a shell for `EXPLAIN (ANALYZE, BUFFERS)`.
- If the Postgres MCP server is configured (see `docs/03-mcp-setup.md`), prefer running
  `EXPLAIN` and reading `pg_stat_statements` through it instead of reasoning from the source.

## Database safety

Any database access Copilot performs goes through the `copilot_perf_reader` role, which is
read-only and carries a `statement_timeout`. Never suggest connecting an agent to a database as
an owner or superuser. MCP-level "read-only mode" is a convenience flag, not a security boundary;
the database role is the boundary. See `db/04-copilot-reader-role.sql`.

Schema changes are proposed as `.sql` files in `db/migrations/` and applied with `make migrate`.
Never issue DDL directly against a live database in a suggestion.

## Style

- Java: constructor injection, no field injection. DTOs are records. Keep `@Transactional`
  read-only where the method only reads.
- SQL: lower-case keywords in migrations are fine, but be explicit about index column order and
  say in a comment which query the index serves.
- React: no premature memoization. Measure a render before optimizing it.
