# 00. Setup

Everything runs locally in Docker. There is no cloud account, no API key, and no external
service involved.

## Prerequisites

| Tool | Why | Check |
| --- | --- | --- |
| Docker Desktop (or Docker Engine + Compose v2) | Runs the whole stack | `docker compose version` |
| `make` | Shortcuts for every command in these docs | `make --version` |
| `curl` and `python3` | Used by `make measure-1` / `make measure-2` | `curl --version` |
| VS Code with GitHub Copilot | The demo itself | Copilot Chat opens |

Give Docker at least 4 GB of memory. The database seeds roughly 1.8 million rows.

You do not need Java, Maven, Node, or PostgreSQL installed. They all run in containers.

## Start it

```bash
git clone https://github.com/sabajamalian/app-scalability-ghcp-usecase.git
cd app-scalability-ghcp-usecase
make up
```

The first run builds three images and seeds the database. Expect **2 to 4 minutes**. Later runs
start in seconds because the seeded volume persists.

While it builds, the database is doing this:

| Table | Rows |
| --- | --- |
| `customers` | 30,000 |
| `products` | 1,000 |
| `orders` | 400,000 |
| `order_items` | ~1,400,000 |

That volume matters. Both defects in this repo are invisible on an empty developer database,
which is exactly why they reach production.

## Verify it is up

```bash
curl -s http://localhost:8080/actuator/health
```

Expected:

```json
{"status":"UP","components":{"db":{"status":"UP",...}}}
```

Then check both scenarios respond:

```bash
make measure-1
make measure-2
```

Expected, approximately (your numbers will differ, the shape will not):

```
sqlQueryCount=219  serverMillis=101  rows=50
sqlQueryCount=1    serverMillis=31   rows=50
```

If you see `219` and `1`, the demo is correctly set up. Those two numbers are the whole story:
scenario 1 is one endpoint issuing 219 statements, scenario 2 is one endpoint issuing a single
statement that is slow. Same symptom to a user, completely different cause, and only one of them
is visible in the source code.

Open the UI at **http://localhost:5173**. Each scenario has a page showing the server-reported
query count and server time next to the browser's wall-clock time.

## What is running

| Service | Port | Notes |
| --- | --- | --- |
| `db` | 5432 | PostgreSQL 17 with `pg_stat_statements` and `hypopg` |
| `backend` | 8080 | Spring Boot 3.5 on Java 25, virtual threads on |
| `frontend` | 5173 | Vite dev server, so Copilot's edits hot-reload |
| `k6` | — | Only runs on demand via `make loadtest-1` / `make loadtest-2` |

Credentials are `demo` / `demo` on database `scaledemo`. They are local-only and deliberately
boring. There is also a read-only role, `copilot_perf_reader`, used by the MCP server; see
[03-mcp-setup.md](03-mcp-setup.md).

## Useful commands

```bash
make help          # list everything
make logs          # tail backend logs
make logs-sql      # tail ONLY the SQL Hibernate emits
make psql          # psql shell as the app user
make psql-reader   # psql shell as the read-only Copilot role
make loadtest-1    # k6 against scenario 1
make loadtest-2    # k6 against scenario 2
make down          # stop, keep the seeded data
make reset         # stop and destroy the data volume
```

## Resetting between runs

Copilot edits real files during this demo, so the repo is dirty afterwards. To run it again:

```bash
make reset
git checkout -- .
git clean -fd db/migrations
make up
```

`make reset` drops the database volume, which removes any index Copilot created. The `git`
commands discard code changes and any migration file it wrote.

## Troubleshooting

**`make up` hangs on the backend.** The database is still seeding. `docker compose logs db` will
show progress. The backend has `restart: unless-stopped` and will connect once the database
finishes.

**Port already in use.** Something else is on 5432, 8080, or 5173. Stop it, or edit the port
mappings in `docker-compose.yml`.

**`make measure-1` prints nothing.** The backend is not up yet. Check
`curl http://localhost:8080/actuator/health`.

**Numbers look different from the docs.** Expected. Absolute latency depends on your hardware.
What should hold is the *ratio* and the query counts: 219 versus 1, and roughly a 3x to 20x
improvement after each fix.

---

Next: [01. Scenario 1, the N+1 that source code makes obvious](01-scenario-n-plus-one.md)
