# Running the same k6 scripts in Azure Load Testing

The scripts in [`loadtest/`](../loadtest/) run locally under Docker by default. They are also
written to upload to Azure Load Testing without modification.

## Why they are portable

Azure Load Testing supports k6 as an engine, but the scripts it runs must be self-contained. So
both scripts in this repo:

- import only from built-in k6 modules (`k6/http`, `k6/metrics`, `k6`),
- import nothing from the local filesystem,
- read the target from `__ENV.BASE_URL` with a local default,
- declare `options.thresholds` in the script itself, so pass/fail travels with the file.

That is the whole portability requirement. If you add a local `import './helpers.js'`, the upload
stops working.

## The constraint to plan for

**Azure Load Testing runs in Azure and cannot reach `http://localhost:8080` on your laptop.**

There is no way around this. The load generators live in Microsoft's network. To run these scripts
in Azure you need the application reachable from there, which means one of:

| Option | When it fits |
| --- | --- |
| Deploy the app to Azure (Container Apps, App Service, AKS) | You want a realistic end-to-end test |
| Deploy behind a public endpoint anywhere | The app is already hosted |
| Use a private endpoint / VNet-injected test | The app is internal-only and you can inject the test into its VNet |

For a private target, Azure Load Testing supports VNet injection: the test engines are deployed
into a subnet in your virtual network and can then reach private IPs. That is the standard answer
for testing a service that is not publicly exposed.

None of this is needed for the demo. Local `make loadtest-1` / `make loadtest-2` gives you the
same numbers on the same scripts.

## Running locally (the default)

```bash
make loadtest-1
make loadtest-2
```

Or directly, against any URL:

```bash
docker compose run --rm -e BASE_URL=https://your-app.example.com k6 run /scripts/scenario-2-search.js
```

## Uploading to Azure Load Testing

1. Create an Azure Load Testing resource.
2. Create a test, choose **Upload a script**, and select `loadtest/scenario-2-search.js`.
3. Set the engine type to **k6**.
4. Add an environment variable `BASE_URL` pointing at your deployed application.
5. Choose the number of engine instances. Each engine runs the full script, so the effective load
   is `engines x vus` from the script's `options`. Adjust `vus` down if you scale engines up, or
   you will run a much larger test than you intended.
6. Run it.

Azure Load Testing reports the k6 thresholds as the test's pass/fail criteria, so the same
`p(95)<150` and `avg<5` assertions that gate the local run gate the cloud run too. You can also
add Azure-side failure criteria on server-side metrics such as CPU or database DTU, which is
worth doing: a load test that only watches client-side latency will not tell you the database was
at 100% CPU.

## Scaling the test up

The local defaults (20 virtual users, 30 seconds) are sized so the demo finishes quickly and
still reproduces both problems. For a real capacity test:

- Raise `vus` and use a ramping profile (`stages`) rather than a flat load, so you can see the
  point where latency turns up rather than just a single data point.
- Run for long enough to get past cache warm-up. Five minutes is a reasonable floor.
- Watch server-side metrics at the same time. Client-side p95 tells you *that* it broke;
  connection-pool saturation and database CPU tell you *where*.
- Keep the thresholds at your SLO, not at current behaviour.

## Alternatives

Nothing in this repository depends on Azure Load Testing. The same scripts run under:

- **k6 Cloud** (Grafana), which is the native hosted option.
- **A self-hosted k6 runner** in your own CI, which is what
  [`.github/workflows/perf-gate.yml`](../.github/workflows/perf-gate.yml) does in its manual job.
- **Any load tool at all**, if you port the two request shapes. The scenarios are just
  `GET /api/orders?limit=50` and
  `GET /api/orders/search?status=SHIPPED&withinHours=48&limit=50`.

The portable part is not the tool. It is that the assertions live in version control next to the
code, and that the test reads `sqlQueryCount` and `serverMillis` out of the response so a failure
tells you whether it got slower because of *more* queries or *slower* queries.
