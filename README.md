# Scaling a web app with GitHub Copilot

A self-service demo. Clone it, run one command, and in about 20 minutes you will have used
GitHub Copilot to diagnose and fix two real scalability defects in a PostgreSQL + Java + React
application, with measurements before and after.

The stack is deliberately ordinary: **PostgreSQL 17, Spring Boot on Java 25, React 19**. Two
performance defects are planted in it on purpose. Everything runs in Docker.

---

## The point of this repo

**An AI assistant's answer on performance is bounded by the evidence it can reach.**

The two scenarios are chosen to show that from both sides.

**Scenario 1** is an N+1 query problem. It is visible in the source code, so Copilot finds it
from the file alone. One endpoint issues **219 SQL statements** per request.

**Scenario 2** is a missing index. The application issues **exactly one** query. The Java is
correct. There is nothing to find in the source.

Ask Copilot about scenario 2 with code context only and you get plausible generic advice: maybe
add an index, maybe cache it, maybe check the pool. Connect it to the database through MCP and
the same question produces a query plan showing a sequential scan discarding 388,562 rows, a
simulated index proving the fix works before anything is written to disk, and a migration with
the evidence in a comment.

Same model, same code, same question. The variable is what you connected it to.

| | before | after | |
| --- | --- | --- | --- |
| **Scenario 1** p95 | 287.24 ms | 82.32 ms | 3.5x |
| SQL statements per request | 219 | 4 | 55x |
| throughput | 97 req/s | 283 req/s | 2.9x |
| **Scenario 2** p95 | 515.3 ms | 22.07 ms | **23x** |
| throughput | 53 req/s | 1865 req/s | **35x** |

All numbers measured, not estimated. Reproduce them yourself.

---

## Start here

```bash
git clone https://github.com/sabajamalian/app-scalability-ghcp-usecase.git
cd app-scalability-ghcp-usecase
make up
```

First run takes 2 to 4 minutes: it builds three images and seeds 400,000 orders with 1.4 million
line items. Then:

```bash
make measure-1   # sqlQueryCount=219  serverMillis=101
make measure-2   # sqlQueryCount=1    serverMillis=31
```

If you see 219 and 1, you are ready.

| | |
| --- | --- |
| **[00. Setup](docs/00-setup.md)** | Prerequisites, one-command start, troubleshooting |
| **[01. Scenario 1: query amplification](docs/01-scenario-n-plus-one.md)** | ~8 min. The bug Copilot can see |
| **[02. Scenario 2: missing index](docs/02-scenario-missing-index.md)** | ~10 min. The bug it cannot see without the database |
| **[03. MCP setup](docs/03-mcp-setup.md)** | ~2 min. And why the DB role, not the MCP flag, is the security boundary |
| **[04. CI enforcement](docs/04-ci-enforcement.md)** | ~3 min. Why instruction files are not a control |
| **[05. Adopt in your own app](docs/05-adopt-in-your-app.md)** | What to copy, in order of return on effort |

You need Docker, `make`, and VS Code with GitHub Copilot. No cloud account, no API keys.

---

## Just want the artifacts?

Every Copilot customization in this repo is stack-agnostic enough to lift directly. Ordered by
return on effort:

| Artifact | Effort | What it does |
| --- | --- | --- |
| [`.github/copilot-instructions.md`](.github/copilot-instructions.md) | 15 min | Repo-wide performance ground rules. "No number, no problem." "Say when you are guessing." |
| [`db/04-copilot-reader-role.sql`](db/04-copilot-reader-role.sql) | 30 min | Read-only PostgreSQL role with statement and lock timeouts. Works on any PG 12+. Worth having even without AI tooling. |
| [`.vscode/mcp.json`](.vscode/mcp.json) | 15 min | Postgres MCP against that role, so Copilot can run `EXPLAIN` instead of guessing |
| [`.github/instructions/`](.github/instructions/) | 30 min | Path-scoped rules for backend, database, and frontend |
| [`.github/prompts/`](.github/prompts/) | 15 min | `/find-n-plus-one`, `/analyze-slow-query`, `/performance-review` |
| [`.github/agents/performance-reviewer.md`](.github/agents/performance-reviewer.md) | 10 min | A custom agent that refuses to speculate without evidence |
| [`.github/workflows/perf-gate.yml`](.github/workflows/perf-gate.yml) | 2-4 hrs | CI gate on SQL statement count. The part that cannot be ignored. |
| [`loadtest/`](loadtest/) | half a day | k6 scripts that run locally and upload to Azure Load Testing unchanged |

[docs/05-adopt-in-your-app.md](docs/05-adopt-in-your-app.md) walks through adapting each one, and
what **not** to copy.

---

## What is in here

```
.github/
  copilot-instructions.md    Repo-wide performance rules and SLOs
  instructions/              Path-scoped rules (backend / db / frontend)
  prompts/                   Reusable slash-command prompts
  agents/                    Read-only performance reviewer agent
  workflows/perf-gate.yml    CI gate on SQL statement count
.vscode/mcp.json             Postgres MCP, read-only role
db/                          Schema, 1.8M-row generate_series seed, reader role
  migrations/                Empty. Copilot writes the fix here during the demo.
backend/                     Spring Boot 3.5, Java 25, virtual threads. Both defects live here.
frontend/                    React 19 + Vite. Shows query count and server time per request.
loadtest/                    k6 scripts with SLO thresholds
docs/                        The guided walkthrough
```

The app is instrumented so evidence arrives with the payload: every API response carries
`sqlQueryCount` and `serverMillis`, and the k6 scripts turn those into trend metrics. You never
have to read a log to know whether something got slower because of *more* queries or *slower*
queries.

---

## Notes

**The fixes are not in this repo.** Copilot writes them during the demo. That is the demo. To
re-run it:

```bash
make reset
git checkout -- .
git clean -fd db/migrations
make up
```

**The CI gate is expected to fail on a clean clone.** The defects are still in place. That is why
[`perf-gate.yml`](.github/workflows/perf-gate.yml) runs on `pull_request` and `workflow_dispatch`
only, never on push to `main`.

**Credentials are local-only demo values** (`demo`/`demo`). Nothing here should be pointed at
production without reading
[docs/03-mcp-setup.md](docs/03-mcp-setup.md#applying-this-to-your-own-database) first.

**Numbers will differ on your hardware.** The reference figures were measured on an Apple Silicon
laptop. The ratios should hold; the absolute milliseconds will not.

---

## Licence

[MIT](LICENSE). Copy anything here into your own repository, commercial or otherwise.
