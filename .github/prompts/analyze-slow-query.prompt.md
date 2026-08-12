---
mode: agent
description: Diagnose a slow query from its plan, simulate the fix with hypopg, then write the migration.
---

# Analyze a slow query

Diagnose `${input:endpoint:Which endpoint or query? e.g. GET /api/orders/search}`.

## 1. Measure

Run the endpoint and record `serverMillis`, then run the matching k6 scenario and record p95 and
throughput. Do not proceed on a hunch.

## 2. Get the plan, not the source

Extract the actual SQL (from `make logs-sql`, or from `pg_stat_statements`) and run:

```sql
EXPLAIN (ANALYZE, BUFFERS) <query>;
```

Also run it with `SET max_parallel_workers_per_gather = 0;` so parallelism does not hide the true
cost on a developer machine.

Report:
- the scan node and its cost,
- actual execution time,
- `Rows Removed by Filter`,
- `Buffers` hit versus read,
- whether the estimate is close to actual (if not, `ANALYZE` first and re-plan).

## 3. Simulate the candidate index before creating it

```sql
SELECT hypopg_reset();
SELECT indexname FROM hypopg_create_index('CREATE INDEX ON <table> (<cols>)');
EXPLAIN <query>;
```

Show the plan before and after. Justify the column order: equality predicates first, then the
range or sort column, and match the sort direction if there is a `LIMIT`.

If the hypothetical index does not change the plan, stop and say so. Do not write a migration for
an index the planner will not use.

## 4. Check the cost of the index

- Does an existing index already cover this predicate as a prefix? Check `pg_indexes`.
- What write volume does this table take? Every index taxes inserts and updates.
- Are there unused indexes on this table (`pg_stat_user_indexes.idx_scan = 0`) that should be
  dropped in the same change?

## 5. Write the migration

Create `db/migrations/NNN-description.sql`. It must:
- start with a comment naming the query it serves and quoting the before/after plan cost,
- use `IF NOT EXISTS`,
- use `CREATE INDEX CONCURRENTLY` for anything that would run against live traffic, with a note
  that it cannot run inside a transaction block.

Do not edit `db/02-schema.sql`.

## 6. Apply and re-measure

`make migrate`, then re-run `EXPLAIN (ANALYZE, BUFFERS)` and the k6 scenario. Present:

| | before | after |
| --- | --- | --- |
| plan node | | |
| execution time | | |
| p95 latency | | |
| requests per second | | |

State the improvement as a multiple, and be honest if the real gain is smaller than the plan cost
suggested.
