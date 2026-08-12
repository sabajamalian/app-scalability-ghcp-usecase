# Load tests

Two k6 scripts, one per demo scenario. They run locally under Docker and upload unchanged to
Azure Load Testing.

```bash
make loadtest-1   # GET /api/orders           (scenario 1: query amplification)
make loadtest-2   # GET /api/orders/search    (scenario 2: missing index)
```

Each runs 20 virtual users for 30 seconds. That is deliberately small: enough to reproduce both
problems, short enough to keep the demo moving.

## What they measure beyond latency

Both scripts read two fields out of the response body and turn them into k6 trend metrics:

| Metric | Source | Tells you |
| --- | --- | --- |
| `sql_queries_per_request` | `sqlQueryCount` in the response | Whether the endpoint is issuing too *many* queries |
| `server_time_ms` | `serverMillis` in the response | How much of the latency is the server, not the network |
| `http_req_duration` | k6 built-in | What the client actually experienced |

That combination is the useful part. When `http_req_duration` regresses, these two tell you
immediately whether the cause is more queries (application code) or slower queries (database).
Without them, that distinction costs an hour of investigation.

## Thresholds

Each script declares thresholds matching the SLOs in
[`.github/copilot-instructions.md`](../.github/copilot-instructions.md):

```js
thresholds: {
  http_req_duration:       ['p(95)<150'],
  sql_queries_per_request: ['avg<5'],
}
```

**These are set to fail before the fix and pass after.** That is the point. A threshold calibrated
to what the system currently does just ratifies the status quo.

Do not soften a threshold to make a run green. If a threshold is wrong, change it deliberately,
with data, and say why.

## Reference results

Measured on an Apple Silicon laptop against the seeded database (400,000 orders, 1.4M order
items). Absolute numbers will differ on your hardware; the ratios should hold.

**Scenario 1** — `GET /api/orders?limit=50`

| | before | after |
| --- | --- | --- |
| SQL statements per request | 219 | 4 |
| p95 | 287.24 ms | 82.32 ms |
| average | 197.45 ms | 31.18 ms |
| throughput | 97.2 req/s | 283.1 req/s |

**Scenario 2** — `GET /api/orders/search?status=SHIPPED&withinHours=48&limit=50`

| | before | after |
| --- | --- | --- |
| SQL statements per request | 1 | 1 |
| p95 | 515.3 ms | 22.07 ms |
| median | 364.85 ms | 6.14 ms |
| server time p95 | 513.5 ms | 14 ms |
| throughput | 53.2 req/s | 1865.2 req/s |

The contrast is the lesson. Scenario 1's 55x reduction in query count bought a 3.5x latency
improvement, because each of those 219 queries was sub-millisecond. Scenario 2's single
`CREATE INDEX` bought 23x. A dramatic-looking metric does not always mean a dramatic user-facing
win, and you only find that out by measuring both sides.

## Running against something other than localhost

```bash
docker compose run --rm -e BASE_URL=https://your-app.example.com k6 run /scripts/scenario-2-search.js
```

Or with k6 installed directly:

```bash
BASE_URL=http://localhost:8080 k6 run loadtest/scenario-1-orders.js
```

## Azure Load Testing

The scripts import only built-in k6 modules and take the target from `__ENV.BASE_URL`, so they
upload without modification. Note that Azure Load Testing runs in Azure and cannot reach a local
Docker Compose app: you need the application deployed, or a VNet-injected test.

Full instructions: [`docs/azure-load-testing.md`](../docs/azure-load-testing.md).

## If you add a script

Keep it self-contained. No local `import` statements, target from `__ENV.BASE_URL` with a
localhost default, thresholds declared in the file. That is what keeps the same file runnable in
three places.
