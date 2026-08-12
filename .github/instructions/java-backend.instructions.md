---
applyTo: "backend/**"
description: Java, Spring Boot, Hibernate and connection-pool rules for performance work.
---

# Java backend performance rules

## Query amplification (N+1)

The single most common scalability defect in this codebase's shape is a lazy association
dereferenced inside a loop or during JSON serialization.

- Before claiming a method is N+1, prove it: hit the endpoint and read `sqlQueryCount` in the
  response envelope, or run `make logs-sql` and count the repeated statements.
- Fix it with a fetch strategy, not by making associations eager. `FetchType.EAGER` on an entity
  fixes one endpoint and slows every other one that touches the entity.
- Valid fixes, roughly in order of preference:
  1. A DTO projection query (JPQL constructor expression or an interface projection) that selects
     exactly the columns the endpoint returns. Cheapest, and it also shrinks the payload.
  2. `@EntityGraph` or an explicit `join fetch` for the associations that endpoint needs.
  3. `@BatchSize` on the *target entity class* to collapse N single-row loads into
     `where id in (...)` batches. Note that in Hibernate 6 `@BatchSize` is not allowed on a
     `@ManyToOne` field; it belongs on the entity being loaded.
- **Pagination trap:** combining `join fetch` on a `@OneToMany` with a `Pageable` makes Hibernate
  apply the limit in memory after loading every matching row (`HHH90003004`). On a large table
  that turns a slow endpoint into an outage. If you need pagination plus collections, either
  paginate ids first and fetch the graph in a second query, or use `@BatchSize`.

## Transactions

- Read paths use `@Transactional(readOnly = true)`.
- Keep transactions short. Never do HTTP calls or long computation inside one; a held connection
  is a pooled resource other requests are waiting for.

## Connection pool

`spring.datasource.hikari.maximum-pool-size` in `application.yml` is deliberately small (10).

The invariant to respect when advising on scale-out:

```
max replicas x maximum-pool-size  <=  postgres max_connections (minus headroom for admin/tools)
```

Doubling replicas without checking this is how a scale-out event takes the database down. If the
pool is saturated, look at `hikaricp_connections_pending` before enlarging the pool. A saturated
pool is usually a symptom of slow queries, not of a small pool.

## Virtual threads

`spring.threads.virtual.enabled=true` is on, and Java 25 includes JEP 491, so `synchronized`
blocks no longer pin a carrier thread. Virtual threads raise concurrency on blocking I/O; they do
not make queries faster. If the database is the bottleneck, more in-flight requests makes the
p99 worse, not better.

## Measurement plumbing already in the repo

- `QueryCountInspector` is a Hibernate `StatementInspector` that counts statements per request in
  a `ThreadLocal`. Hibernate instantiates it by class name, not through Spring, so the counter is
  static by necessity.
- `MeasuredResponse<T>` wraps every endpoint response with `sqlQueryCount` and `serverMillis`, so
  evidence arrives with the payload instead of in a log file.
- Use these rather than adding new timing code.

## Regression protection

A performance fix that is not covered by a test will be undone by the next refactor. When you fix
a query-count problem, add or extend a test that asserts the statement count, in the shape of
`backend/src/test/java/com/example/scaledemo/OrderQueryCountTest.java`. Assert a bound, not an
exact number, so a harmless extra statement does not create a flaky test.
