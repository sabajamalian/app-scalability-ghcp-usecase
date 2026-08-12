---
applyTo: "db/**"
description: PostgreSQL indexing, EXPLAIN discipline and migration rules.
---

# PostgreSQL performance rules

## Read the plan before proposing anything

Never recommend an index from reading application code alone. Get the plan first:

```sql
EXPLAIN (ANALYZE, BUFFERS) <the actual query>;
```

What to look for, and what it means:

- `Seq Scan` with a large `Rows Removed by Filter` on a big table: a missing or unusable index.
- `Rows` estimate far from `actual rows`: stale statistics. Run `ANALYZE` before you touch indexes.
- High `read=` in `Buffers`: the working set is not cached, so the plan is paying real I/O.
- `Sort` feeding a small `LIMIT`: an index whose order matches the `ORDER BY` can remove the sort
  entirely.
- Parallel workers can mask a bad plan on a developer machine. To see the serial cost, run
  `SET max_parallel_workers_per_gather = 0;` first.

## Simulate before you migrate

`hypopg` is installed. Create a hypothetical index and re-plan without writing anything to disk:

```sql
SELECT hypopg_reset();
SELECT indexname FROM hypopg_create_index('CREATE INDEX ON orders (status, placed_at DESC)');
EXPLAIN <the query>;   -- plain EXPLAIN; ANALYZE cannot use a hypothetical index
```

If the plan does not change, the index is not worth building. This is the cheapest way to kill a
bad index idea before it costs a maintenance window.

## Index design

- Column order in a composite index matters: equality predicates first, then the range or sort
  column. `(status, placed_at)` serves `status = ? AND placed_at >= ?`; `(placed_at, status)`
  does not serve it nearly as well.
- Match the index's sort direction to the query's `ORDER BY` when a `LIMIT` is involved.
- Every index costs write throughput and storage. Before adding one, check whether an existing
  index already covers the predicate as a prefix.
- Look for unused indexes with `pg_stat_user_indexes` (`idx_scan = 0`) before adding more.
- On a table with live traffic, always `CREATE INDEX CONCURRENTLY`. It cannot run inside a
  transaction block, so it goes in its own migration file with a comment saying why.

## Finding the expensive queries

`pg_stat_statements` is enabled. Rank by total time, not by mean, because the thing hurting the
system is often a fast query called an enormous number of times:

```sql
SELECT calls, round(mean_exec_time::numeric, 2) AS mean_ms,
       round(total_exec_time::numeric, 2) AS total_ms, query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

High `calls` with low `mean_exec_time` is the signature of application-side query amplification
(N+1), not of a slow query. The fix for that lives in `backend/`, not here.

## Migrations

- Schema changes go in `db/migrations/` as `NNN-description.sql`, applied with `make migrate`.
- Every migration starts with a comment naming the query it serves and the before/after plan cost
  or timing that justifies it.
- Use `IF NOT EXISTS` so re-running is safe.
- Never edit `db/02-schema.sql` to add a fix. That file is the demo's starting state.

## Deliberate defects in this repo

`db/02-schema.sql` intentionally omits an index on `orders (status, placed_at)`. That omission is
scenario 2 of the demo. Do not add it to the schema file; the point is for the user to discover
it from a query plan and write the migration.
