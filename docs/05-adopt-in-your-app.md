# 05. Adopting this in your own application

You do not need to keep the sample app. Most of the value here is in six artifacts you can copy
into your own repository this afternoon.

Ordered by return on effort.

---

## 1. `.github/copilot-instructions.md` (15 minutes)

**Copy:** [`.github/copilot-instructions.md`](../.github/copilot-instructions.md)

Replace the stack section and the SLO table with yours. Keep the performance ground rules almost
verbatim; they are stack-independent. The two that change answers most:

- *No number, no problem.* Nothing is slow until it has a measurement.
- *Say when you are guessing.* Forces the assistant to distinguish a hypothesis from a diagnosis,
  which is the difference [scenario 2](02-scenario-missing-index.md) is built to show.

Fill in the SLO table with numbers your team has actually agreed to. If you do not have any, that
is the finding, and it is worth more than any tooling change.

## 2. A read-only database role (30 minutes)

**Copy:** [`db/04-copilot-reader-role.sql`](../db/04-copilot-reader-role.sql)

This is the most reusable file in the repository and it works on any PostgreSQL 12 or later. It
is worth creating even if you never connect an AI tool to it, because it is also the right role
for a human doing performance investigation.

Adapt: change the password (use your secret manager), point it at a replica if you have one, and
consider column-level grants if the tables hold personal data. See
[03-mcp-setup.md](03-mcp-setup.md#applying-this-to-your-own-database) for the full checklist.

For MySQL, the equivalent is a user with `SELECT` and `PROCESS` privileges plus
`max_execution_time`. For SQL Server, a login mapped to `db_datareader` with
`VIEW DATABASE STATE` and a query governor cost limit.

## 3. Postgres MCP with the restricted role (15 minutes)

**Copy:** [`.vscode/mcp.json`](../.vscode/mcp.json)

Point `DATABASE_URI` at a staging database with **production-shaped data volume**. Not production
itself, and not an empty developer database. Volume is what makes performance defects visible;
scenario 2 does not reproduce at all on 100 rows.

For team-wide rollout, move this to `.mcp.json` at the repo root or configure it centrally, and
inject the connection string from your secret store rather than committing it. The value here is
committed only because the credentials are local-only demo values.

## 4. Path-scoped instruction files (30 minutes)

**Copy:** [`.github/instructions/`](../.github/instructions/)

Three files, each with an `applyTo` glob. The pattern matters more than the content: rules that
only apply to database work should not consume context while someone edits a React component.

Map to your layout, then replace the content with your team's actual hard-won rules. The most
valuable entries in ours are the ones that encode a bug we hit:

- `@BatchSize` is not allowed on `@ManyToOne` in Hibernate 6.
- `join fetch` on a `@OneToMany` plus `Pageable` paginates in memory.
- `max replicas x pool size <= max_connections`.

Every team has three or four of these. Writing them down is the highest-value thing in this
entire repository, and it is worth doing whether or not you use Copilot.

## 5. A performance gate in CI (2 to 4 hours)

**Copy:** [`.github/workflows/perf-gate.yml`](../.github/workflows/perf-gate.yml) and
[`OrderQueryCountTest.java`](../backend/src/test/java/com/example/scaledemo/OrderQueryCountTest.java)

Pick your single most expensive endpoint and assert a bound on its SQL statement count. Not a
percentile: statement counts are deterministic and will not flake on a shared runner.

If you are not on Hibernate, the equivalent instrumentation is:

| Stack | Mechanism |
| --- | --- |
| Hibernate / JPA | `StatementInspector`, or `SessionFactory.getStatistics()` |
| Spring JDBC | A `DataSource` proxy such as datasource-proxy or p6spy |
| Rails | `ActiveSupport::Notifications` on `sql.active_record` |
| Django | `django.test.utils.CaptureQueriesContext` or `assertNumQueries` |
| Node / Prisma | A query event listener |
| Go / `database/sql` | A wrapping driver |

Assert a bound with headroom, and put the reasoning in the failure message. A test that fails
with "expected 4, got 5" gets deleted. One that explains what regressed and how to reproduce it
gets fixed. See [04-ci-enforcement.md](04-ci-enforcement.md).

## 6. Load tests that live in the repo (half a day)

**Copy:** [`loadtest/`](../loadtest/)

The k6 scripts use only built-in imports so the same file runs locally under Docker and uploads
unchanged to Azure Load Testing. See [azure-load-testing.md](azure-load-testing.md).

Two things worth stealing regardless of tool:

- **Custom metrics from the response body.** The API returns `sqlQueryCount` and `serverMillis`,
  and the k6 scripts turn those into trend metrics. So a load test reports not just *that* it got
  slower but *why*: more queries, or slower queries. That distinction usually costs an hour of
  investigation.
- **Thresholds set to the SLO, not to current behaviour.** A threshold calibrated to what the
  system does today ratifies the status quo. Set it to what you promised, let it fail, and treat
  the failure as the backlog item it is.

---

## What not to copy

**The planted defects.** `OrderService.listRecentOrders` and the missing index exist to be found.
Do not carry them into your codebase.

**`QueryCountInspector` as production code.** It is a static `ThreadLocal` counter, which is fine
for a demo and wrong for a real system. Use Hibernate's own statistics or OpenTelemetry JDBC
instrumentation instead.

**The Compose file.** It is tuned for a single-machine demo: no resource limits, no TLS,
hard-coded credentials, and a Vite dev server rather than a production build.

---

## A realistic sequencing

If you are introducing this to a team, the order that tends to work:

1. **Week 1:** write the instruction files. Cheap, immediately useful, and the discussion about
   what belongs in them is more valuable than the files.
2. **Week 2:** create the read-only role and wire up MCP against staging. Run
   [scenario 2](02-scenario-missing-index.md) against your own database and find your own
   sequential scan. Most teams find one within an hour.
3. **Week 3:** add one CI gate on your most expensive endpoint. One is enough to establish the
   pattern.
4. **Later:** load tests in CI, more gates, plan-shape assertions.

Do not do all of it at once. The instruction files alone change the quality of the answers you
get, and they cost an afternoon.

---

## The one thing to take away

Copilot is good at performance work in proportion to the evidence it can reach.

Given source code alone, it produces plausible generic advice, and some of it is even right.
Given a query plan, `pg_stat_statements`, and a load-test percentile, it produces a specific
diagnosis with the evidence attached.

Same model. Same question. The variable is what you connected it to.
