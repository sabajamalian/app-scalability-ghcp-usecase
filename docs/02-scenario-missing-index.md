# 02. Scenario 2: the missing index

**Time: about 10 minutes.**

`GET /api/orders/search?status=SHIPPED&withinHours=48&limit=50` issues **exactly one** SQL
statement. The Java is fine. There is nothing to find in the source code.

Under load it collapses to a p95 of **515 ms** and 53 requests per second.

This is the scenario that makes the argument. Scenario 1 was solvable from source. This one is
not, and it shows what changes when Copilot can reach the database instead of guessing from code.

---

## Step 1. Get a number

```bash
make measure-2
```

Observed:

```
sqlQueryCount=1  serverMillis=31  rows=50
```

One query, 31 ms. On a single request that looks completely healthy. Now apply concurrency:

```bash
make loadtest-2
```

Observed (20 virtual users, 30 seconds):

```
server_time_ms......: avg=370.3    med=361     p(95)=513.5
http_req_duration...: avg=373.2ms med=364.85ms p(95)=515.3ms max=726.21ms
http_reqs...........: 1611   53.2/s

THRESHOLDS
  http_req_duration
    ✗ 'p(95)<150' p(95)=515.3ms
  server_time_ms
    ✗ 'p(95)<50'  p(95)=513.5
```

**Checkpoint:** 31 ms alone, 515 ms at p95 under 20 users, and throughput stuck at 53 requests
per second. A single-user smoke test would have passed this endpoint. That gap between
"works on my machine" and "falls over at 20 users" is the entire reason load testing exists.

Note the difference from scenario 1: `sqlQueryCount` is 1. Whatever is wrong, it is not the
application issuing too many queries.

## Step 2. Ask Copilot with code context only

This is the important half of the demo. **Do not connect MCP yet.**

Open Copilot Chat, add `backend/src/main/java/com/example/scaledemo/service/OrderService.java`
and `backend/src/main/java/com/example/scaledemo/repo/OrderRepository.java`, and ask:

> `GET /api/orders/search` has a p95 of 515 ms under 20 concurrent users. It issues exactly one
> SQL query. What is wrong and how do I fix it?

**What you will typically get:** a list of plausible, generic possibilities. Something like:
add an index (maybe on `status`, maybe on `placed_at`, maybe both, usually without a column
order or a reason for one), consider caching, consider pagination, consider a read replica,
check the connection pool.

Some of that is even right. But notice what it cannot tell you:

- Which plan PostgreSQL is actually choosing.
- How many rows the filter is discarding.
- Whether the proposed index would change the plan at all.
- Whether the statistics are stale, which would make any index advice premature.

It is reasoning from the shape of the code, because that is all it has. Read the answer to your
audience and label it honestly: **this is a hypothesis, not a diagnosis.** The repository's own
instructions require Copilot to say so
(`.github/copilot-instructions.md`, "Say when you are guessing").

## Step 3. Look at what Copilot could not see

```bash
make psql
```

```sql
SET max_parallel_workers_per_gather = 0;   -- see the true serial cost

EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.order_ref, o.status, o.total_cents, o.placed_at
FROM orders o
WHERE o.status = 'SHIPPED'
  AND o.placed_at >= now() - interval '48 hours'
ORDER BY o.placed_at DESC
LIMIT 50;
```

Observed:

```
 Limit  (cost=27435.74..27435.86 rows=50 width=16) (actual time=135.560..135.567 rows=50 loops=1)
   Buffers: shared hit=16041 read=3010
   ->  Sort  (cost=27435.74..27464.92 rows=11672 width=16) (actual time=135.558..135.561 rows=50 loops=1)
         Sort Key: placed_at DESC
         Sort Method: top-N heapsort  Memory: 28kB
         ->  Seq Scan on orders o  (cost=0.00..27048.00 rows=11672 width=16) (actual time=0.217..134.386 rows=11438 loops=1)
               Filter: ((status = 'SHIPPED'::text) AND (placed_at >= (now() - '48:00:00'::interval)))
               Rows Removed by Filter: 388562
 Planning Time: 0.593 ms
 Execution Time: 135.622 ms
```

Read it out loud:

- **`Seq Scan on orders`** — PostgreSQL is reading the entire table.
- **`Rows Removed by Filter: 388562`** — it examined 400,000 rows to return 50. It threw away
  99.99% of the work it did.
- **`Buffers: shared hit=16041 read=3010`** — 19,000 buffer accesses, 3,010 of them actual reads
  from disk. Multiply that by 20 concurrent users and you have the throughput ceiling.
- **`Sort`** feeding a `LIMIT 50` — it sorted the whole filtered set to return the top 50.
- The estimate (11,672) is close to actual (11,438), so statistics are fine. Nothing to fix there.

None of that is inferable from the Java. `.github/instructions/postgres.instructions.md` tells
Copilot to run exactly this before recommending anything, but it needs a way to run it.

## Step 4. Connect MCP and ask again

Set up the Postgres MCP server now if you have not: [03-mcp-setup.md](03-mcp-setup.md). It takes
about two minutes.

Then ask again:

> `GET /api/orders/search` has a p95 of 515 ms. Run `EXPLAIN (ANALYZE, BUFFERS)` on the query it
> issues, tell me what the plan is doing, and propose an index. Simulate the index with `hypopg`
> before writing a migration.

Or use the packaged prompt: `/analyze-slow-query`.

**What changes.** Copilot now runs the query plan itself, reads `Rows Removed by Filter`, and
reasons from the actual plan rather than from the file. The answer stops being a list of
possibilities and becomes a specific claim with evidence attached. That difference is the demo.
Show the two answers side by side.

## Step 5. Simulate the index before creating it

This is the part that surprises people. `hypopg` is installed, so you can create a *hypothetical*
index that exists only in the current session's memory and ask the planner to re-plan against it.
Nothing is written to disk. No lock is taken. It costs milliseconds.

```sql
SELECT hypopg_reset();
SELECT indexname FROM hypopg_create_index('CREATE INDEX ON orders (status, placed_at DESC)');

EXPLAIN
SELECT o.id, o.order_ref, o.status, o.total_cents, o.placed_at
FROM orders o
WHERE o.status = 'SHIPPED'
  AND o.placed_at >= now() - interval '48 hours'
ORDER BY o.placed_at DESC
LIMIT 50;
```

Observed:

```
 Limit  (cost=0.05..149.58 rows=50 width=16)
   ->  Index Scan using "<13566>btree_orders_status_placed_at" on orders o
         (cost=0.05..34902.71 rows=11671 width=16)
         Index Cond: ((status = 'SHIPPED'::text) AND (placed_at >= (now() - '48:00:00'::interval)))
```

**Checkpoint:** the `Limit` cost drops from **27,435 to 149.58**, the `Seq Scan` becomes an
`Index Scan`, and the `Sort` disappears entirely because the index already delivers rows in
`placed_at DESC` order, so the `LIMIT 50` can stop after 50 rows.

Use plain `EXPLAIN`, not `EXPLAIN ANALYZE`. A hypothetical index cannot be executed against, only
planned against.

Two things worth saying here:

- If the plan had *not* changed, you would have just avoided building a useless index. That is
  the real value: `hypopg` lets you kill a bad index idea for free instead of discovering it was
  useless after a maintenance window.
- The column order is not arbitrary. `(status, placed_at DESC)` puts the equality predicate first
  and the range/sort column second. `(placed_at, status)` would be substantially worse. Ask
  Copilot to justify the order; a good answer explains this.

## Step 6. Let Copilot write the migration

Ask it to write the migration into `db/migrations/`. Expected shape:

```sql
-- db/migrations/001-orders-status-placed-at.sql
--
-- Serves: GET /api/orders/search
-- Before: Seq Scan, cost 27048, 135 ms serial, 388,562 rows removed by filter
-- After (hypopg): Index Scan, Limit cost 149.58, no sort node
--
-- Column order: equality predicate (status) first, then range/sort column.
-- DESC matches ORDER BY so LIMIT can stop early.

CREATE INDEX IF NOT EXISTS idx_orders_status_placed_at
    ON orders (status, placed_at DESC);
```

For a table taking live writes it should use `CREATE INDEX CONCURRENTLY`, which cannot run inside
a transaction block and therefore needs its own migration file. Ask Copilot about production
safety if it does not raise this itself.

Apply it:

```bash
make migrate
```

## Step 7. Re-measure

```bash
make loadtest-2
```

Reference result:

| | before | after | change |
| --- | --- | --- | --- |
| plan | Seq Scan + Sort | Index Scan | — |
| p95 latency | 515.3 ms | **22.07 ms** | **23x faster** |
| median latency | 364.85 ms | **6.14 ms** | 59x faster |
| server time p95 | 513.5 ms | **14 ms** | 37x faster |
| throughput | 53.2 req/s | **1865.2 req/s** | **35x more** |

```
server_time_ms......: avg=4.63    med=3       p(95)=14
http_req_duration...: avg=8.31ms  med=6.14ms  p(95)=22.07ms
http_reqs...........: 55981   1865.2/s
```

Both thresholds pass.

**Checkpoint:** compare this against scenario 1's 3.5x. One `CREATE INDEX` bought a 23x latency
improvement and a 35x throughput improvement. It was invisible in the source code, invisible in
a single-user test, and would have been guessed at rather than diagnosed without access to the
query plan.

That is the argument this repository exists to make: **an AI assistant's answer on performance is
bounded by the measurements it can reach.** Same model, same code, same question. What changed
was the evidence available to it.

---

## Reset

```bash
make reset && make up
```

The index lives in the database volume, so dropping the volume removes it. Also remove the
migration Copilot wrote:

```bash
git clean -fd db/migrations
```

Next: [03. Wiring up Postgres MCP](03-mcp-setup.md)
