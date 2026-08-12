# 03. Wiring up Postgres MCP

**Time: about 2 minutes.**

Model Context Protocol (MCP) lets Copilot call tools. A Postgres MCP server gives it the ability
to run `EXPLAIN`, read `pg_stat_statements`, and inspect the schema, instead of inferring all of
that from your source code.

[Scenario 2](02-scenario-missing-index.md) is the demonstration of why that matters.

## The config

`.vscode/mcp.json` is already in this repository:

```json
{
  "servers": {
    "postgres": {
      "type": "stdio",
      "command": "docker",
      "args": ["run", "-i", "--rm", "-e", "DATABASE_URI",
               "crystaldba/postgres-mcp", "--access-mode=restricted"],
      "env": {
        "DATABASE_URI": "postgresql://copilot_perf_reader:copilot_demo_readonly@host.docker.internal:5432/scaledemo"
      }
    }
  }
}
```

Open the repo in VS Code, open `.vscode/mcp.json`, and click **Start** on the server entry. Then
in Copilot Chat open the tools picker and confirm the Postgres tools are listed.

On Linux, `host.docker.internal` may not resolve. Either add
`--add-host=host.docker.internal:host-gateway` to the `args`, or use `--network=host` with
`localhost` in the URI.

## Verify it works

Ask Copilot:

> Using the postgres tools, list the indexes on the `orders` table.

You should get `orders_pkey` and `idx_orders_customer_id`, and nothing on `(status, placed_at)`.
That absence is scenario 2.

Then:

> Run `EXPLAIN (ANALYZE, BUFFERS)` on:
> `SELECT id FROM orders WHERE status = 'SHIPPED' AND placed_at >= now() - interval '48 hours' ORDER BY placed_at DESC LIMIT 50;`

If you get a real plan back with `Seq Scan` and `Rows Removed by Filter`, MCP is working.

## The part that actually matters: the database role

Read this section even if you skip the rest.

The MCP server runs with `--access-mode=restricted`. That flag is a **convenience, not a security
boundary.** It is a filter inside a process that is, by design, driven by model output. Treat it
the way you would treat client-side validation.

The real boundary is the PostgreSQL role. `db/04-copilot-reader-role.sql` creates it:

```sql
CREATE ROLE copilot_perf_reader LOGIN PASSWORD 'copilot_demo_readonly';

ALTER ROLE copilot_perf_reader SET default_transaction_read_only = on;
ALTER ROLE copilot_perf_reader SET statement_timeout = '15s';
ALTER ROLE copilot_perf_reader SET lock_timeout = '2s';
ALTER ROLE copilot_perf_reader SET idle_in_transaction_session_timeout = '30s';

GRANT pg_read_all_stats TO copilot_perf_reader;
REVOKE CREATE ON SCHEMA public FROM copilot_perf_reader;
```

Each line is doing a specific job:

| Setting | What it prevents |
| --- | --- |
| `default_transaction_read_only` | Any write, whatever the MCP layer allows through |
| `statement_timeout = 15s` | An `EXPLAIN ANALYZE` on a bad query pinning a core |
| `lock_timeout = 2s` | An analysis session blocking application traffic |
| `idle_in_transaction_session_timeout` | An abandoned session holding a snapshot and blocking vacuum |
| `REVOKE CREATE ON SCHEMA public` | Creating objects even in a session that somehow became writable |
| `GRANT pg_read_all_stats` | *Enables* reading `pg_stat_statements` without granting anything else |

You can verify the boundary yourself:

```bash
make psql-reader
```

```sql
DELETE FROM orders WHERE id = 1;
-- ERROR:  cannot execute DELETE in a read-only transaction

SELECT count(*) FROM orders;
--  400000

SELECT count(*) FROM pg_stat_statements;
--  81
```

## Why `hypopg` still works under a read-only role

This is the detail people expect to break. It does not:

```sql
SELECT indexname FROM hypopg_create_index('CREATE INDEX ON orders (status, placed_at DESC)');
-- works, even with default_transaction_read_only = on
```

`hypopg` stores the hypothetical index in session memory only. It never touches disk, so the
read-only transaction setting does not block it. The practical consequence is good: a strictly
read-only analysis role can still evaluate whether an index would help, before anyone takes a
lock on a production table.

## Applying this to your own database

Do not point this at production without thinking it through.

1. **Use a replica if you have one.** `EXPLAIN ANALYZE` executes the query. On a primary under
   load that is real work.
2. **Create the role, do not reuse the application user.** The application user can write.
3. **Consider column-level grants or a masked view** if the tables contain personal data. A
   read-only role can still read everything it is granted, and query results flow into a model's
   context. That is a data-governance decision, not just a security one.
4. **Log it.** Sessions from this role should be identifiable in `pg_stat_activity` and in your
   audit trail.
5. **Prefer a staging database with production-shaped data volume.** Most performance defects
   need realistic row counts, not real customer data. This demo makes that case: 400,000
   synthetic rows are enough to reproduce a 20x problem.

## Alternative servers

`crystaldba/postgres-mcp` is used here because it bundles index-tuning and health analysis on top
of plain query execution. Other options exist, including the reference PostgreSQL MCP server and
vendor-specific ones from cloud providers. The security guidance above applies to all of them
without change: **the database role is the boundary.**

---

Next: [04. Why CI enforcement matters more than instruction files](04-ci-enforcement.md)
