# 01. Scenario 1: query amplification (N+1)

**Time: about 8 minutes.**

The endpoint `GET /api/orders?limit=50` returns 50 orders with their customer and line items. It
issues **219 SQL statements** to do it. Every statement is fast. That is what makes this defect
survive code review and load-free testing.

This scenario is the *easy* case for an AI assistant: the bug is visible in the source. Run it
first so the contrast with scenario 2 lands.

---

## Step 1. Get a number

Never call something slow before you have measured it.

```bash
make measure-1
```

Observed on the reference machine:

```
sqlQueryCount=219  serverMillis=101  rows=50
```

Now under concurrency:

```bash
make loadtest-1
```

Observed (20 virtual users, 30 seconds):

```
sql_queries_per_request...: avg=219      min=219     med=219     max=219
http_req_duration.........: avg=197.45ms med=168.09ms p(95)=287.24ms max=348.7ms
http_reqs.................: 2931   97.2/s

THRESHOLDS
  http_req_duration
    ✗ 'p(95)<150' p(95)=287.24ms
  sql_queries_per_request
    ✗ 'avg<5' avg=219
```

**Checkpoint:** both thresholds fail, `sql_queries_per_request` is pinned at exactly 219, and
throughput is around 97 requests per second. The query count is identical on every request,
which tells you this is structural rather than a caching artifact.

## Step 2. See the amplification

```bash
make logs-sql
```

Hit the endpoint again in another terminal (`make measure-1`) and watch. You will see one
`select ... from orders` followed by the same `select ... from customers where id=?` and
`select ... from order_items where order_id=?` scrolling past over and over.

Press `Ctrl+C` when the point is made.

Where 219 comes from:

| Statements | Source |
| --- | --- |
| 1 | the base `select ... from orders order by id desc limit 50` |
| 50 | one `customers` load per order (`order.getCustomer()`) |
| 50 | one `order_items` load per order (`order.getItems()`) |
| ~118 | one `products` load per distinct product across those items |

Products repeat across orders, and Hibernate's persistence context deduplicates within the
transaction, which is why the last number is not a round 150.

## Step 3. Ask Copilot with code context only

Open Copilot Chat. Add `backend/src/main/java/com/example/scaledemo/service/OrderService.java`
to the context and ask:

> `GET /api/orders` has a p95 of 170 ms under 20 concurrent users and issues 219 SQL statements
> per request. Find the cause and propose the smallest fix.

Or use the packaged prompt: `/find-n-plus-one`.

**What to expect.** Copilot should find this quickly and correctly. The lazy associations are
dereferenced in plain sight inside `listRecentOrders`, and the repository method is right there.
A good answer names `getCustomer()`, `getItems()`, and `getProduct()` specifically, and does the
1 + 50 + 50 + N arithmetic.

**What to watch for.** Two failure modes are common, and both are worth pointing out to your
audience:

1. **Suggesting `FetchType.EAGER`.** This fixes one endpoint and slows down every other code path
   that touches `Order`. The repository's instruction files
   (`.github/instructions/java-backend.instructions.md`) explicitly rule it out. If Copilot
   suggests it anyway, that is a live demonstration of why instructions are advisory and CI is
   enforcement.
2. **Suggesting `join fetch` on the collection while keeping `Pageable`.** This is subtly worse
   than the original bug: Hibernate cannot apply a SQL `LIMIT` to a fetched `@OneToMany`, so it
   loads every matching row into memory and paginates there (`HHH90003004`). On 400,000 orders
   that is an outage, not an optimization. If Copilot proposes it, ask: *"what happens to that
   query with 400,000 orders in the table?"*

## Step 4. Ask again with MCP connected

If you have set up the Postgres MCP server ([03-mcp-setup.md](03-mcp-setup.md)), ask again:

> Check `pg_stat_statements` and tell me what the query pattern for `/api/orders` looks like.

Now Copilot can see the signature directly:

```sql
SELECT calls, round(mean_exec_time::numeric, 3) AS mean_ms,
       round(total_exec_time::numeric, 1) AS total_ms, query
FROM pg_stat_statements
ORDER BY calls DESC
LIMIT 5;
```

The `customers` and `order_items` lookups show **very high `calls`** with **sub-millisecond
`mean_exec_time`**. That combination is the fingerprint of application-side amplification, and it
is the opposite of what most people go looking for. Ranking by `mean_exec_time` would never
surface it; ranking by `calls` or `total_exec_time` puts it at the top.

This is the honest framing for scenario 1: MCP is a *confirmation* here, not a revelation.
Scenario 2 is where it changes the answer.

## Step 5. Let Copilot fix it

Ask it to apply the fix. Acceptable approaches, roughly in order of preference:

1. A DTO projection query that selects exactly the columns the endpoint returns.
2. `@EntityGraph` or `join fetch` for the to-one associations, with the collection handled
   separately.
3. `@BatchSize` on the *target entity classes* (`Customer`, `Product`) and on the `items`
   collection, which collapses the per-row loads into `where id in (...)` batches.

Note for option 3: in Hibernate 6, `@BatchSize` is **not** allowed on a `@ManyToOne` field. It
goes on the entity class being loaded. If Copilot puts it on the field, the application fails to
start with `Property 'customer' may not be annotated '@BatchSize'`. That is a real error we hit
while building this demo, and it is a good moment to show Copilot reading the stack trace and
correcting itself.

Rebuild and re-measure:

```bash
docker compose up -d --build backend
make measure-1
make loadtest-1
```

## Step 6. Confirm the number moved

Reference result, using the `@BatchSize` fix:

| | before | after | change |
| --- | --- | --- | --- |
| SQL statements per request | 219 | **4** | 55x fewer |
| p95 latency | 287.24 ms | **82.32 ms** | 3.5x faster |
| average latency | 197.45 ms | **31.18 ms** | 6.3x faster |
| throughput | 97.2 req/s | **283.1 req/s** | 2.9x more |

```
sql_queries_per_request...: avg=4       min=4      med=4      max=4
http_req_duration.........: avg=31.18ms med=23.28ms p(95)=82.32ms
http_reqs.................: 8500   283.1/s
```

Both thresholds now pass.

**Checkpoint:** the p95 improvement (3.5x) is much smaller than the query-count improvement (55x).
Say that out loud. 219 fast queries cost real time but not proportionally, because each one was
sub-millisecond. This is a useful corrective to the instinct that a dramatic-looking metric
implies a dramatic user-facing win. The throughput number is the one that matters at scale: the
same database now serves 2.9x the traffic.

## Step 7. Protect the fix

A performance fix with no test gets reverted by the next refactor.

```bash
make test
```

`backend/src/test/java/com/example/scaledemo/OrderQueryCountTest.java` asserts a bound on the
statement count. Before the fix it fails with a message that names the number and points back to
this document. After the fix it passes.

This is the same job `.github/workflows/perf-gate.yml` does on every pull request. See
[04-ci-enforcement.md](04-ci-enforcement.md) for why that matters more than the instruction
files do.

---

## Reset before the next scenario

```bash
git checkout -- backend/
docker compose up -d --build backend
make measure-1   # should print 219 again
```

Next: [02. Scenario 2, the problem the source code cannot show you](02-scenario-missing-index.md)
