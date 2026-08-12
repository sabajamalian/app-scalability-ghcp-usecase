# Migrations

Schema changes live here as `NNN-description.sql` and are applied with:

```bash
make migrate
```

`make migrate` runs every `.sql` file in this directory in filename order, with
`ON_ERROR_STOP=1`, against the running demo database.

This is deliberately a plain-SQL setup rather than Flyway or Liquibase. The demo is about the
reasoning behind a schema change, not about migration tooling, and a `.sql` file is something you
can read, review, and lift into whatever your team already uses.

## Rules for a migration in this repo

1. Start with a comment naming the query the change serves, and the before/after plan evidence
   that justifies it. A migration without evidence is a guess with a version number.
2. Use `IF NOT EXISTS` so re-running is safe.
3. For anything that would run against live traffic, use `CREATE INDEX CONCURRENTLY`. It cannot
   run inside a transaction block, so it needs its own file and a comment saying why.
4. Never edit `db/02-schema.sql` to apply a fix. That file is the demo's starting state and the
   planted problems live there on purpose.

## Example shape

```sql
-- Serves: GET /api/orders/search
--   SELECT ... FROM orders WHERE status = ? AND placed_at >= ? ORDER BY placed_at DESC LIMIT ?
--
-- Before: Seq Scan on orders, cost 27048, 135 ms serial, 388,562 rows removed by filter
-- After (hypopg simulation): Index Scan, cost 0.05..149.58
--
-- Column order: equality predicate (status) first, then the range/sort column (placed_at).
-- DESC matches the ORDER BY so the LIMIT can stop early instead of sorting.

CREATE INDEX IF NOT EXISTS idx_orders_status_placed_at
    ON orders (status, placed_at DESC);
```

During the demo this directory starts empty. Copilot writes the file.
