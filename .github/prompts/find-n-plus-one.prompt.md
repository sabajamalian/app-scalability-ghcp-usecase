---
mode: agent
description: Find query amplification (N+1) in a request path and prove it with a query count.
---

# Find the N+1

Find query amplification in the request path for `${input:endpoint:Which endpoint? e.g. GET /api/orders}`.

Work in this order and do not skip ahead.

## 1. Establish the number first

Get an actual statement count before forming any theory:

- `make measure-1` (or curl the endpoint) and read `sqlQueryCount` from the response envelope.
- Or run `make logs-sql`, hit the endpoint once, and count the repeated statements.

State the count you observed. If you cannot run anything, say so explicitly and label everything
that follows as a hypothesis.

## 2. Locate the amplification

Trace from the controller to the repository. Identify every lazy association that gets
dereferenced after the transaction's initial query, including during JSON serialization. Name the
specific field and the line where it is touched.

Report it as: one base query plus N of *this* statement plus M of *that* statement, and show that
the arithmetic matches the count you measured in step 1. If it does not match, you have not found
all of it yet.

## 3. Confirm from the database side, if you can

If the Postgres MCP server is available, check `pg_stat_statements` for the signature: high
`calls`, low `mean_exec_time`, high `total_exec_time`. That pattern is amplification, not a slow
query. Include the row.

## 4. Propose the fix

Give the cheapest fix that removes the amplification, and say why you chose it over the
alternatives (DTO projection, `@EntityGraph` / `join fetch`, `@BatchSize`).

Call out explicitly whether your fix interacts with pagination. A `join fetch` on a `@OneToMany`
combined with `Pageable` makes Hibernate paginate in memory, which is worse than the original
problem on a large table.

## 5. Predict, then verify

Before applying anything, state the query count you expect afterwards. Then apply the fix,
rebuild, re-measure, and put the numbers side by side:

| | before | after |
| --- | --- | --- |
| SQL statements per request | | |
| p95 latency (`make loadtest-1`) | | |
| requests per second | | |

If the number did not move as predicted, say that plainly and explain what you got wrong.

## 6. Protect it

Add or extend a test that asserts a bound on the statement count, so the next refactor cannot
silently reintroduce the problem.
