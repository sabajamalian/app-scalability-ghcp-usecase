---
mode: agent
description: Review a change for scalability risk before it merges.
---

# Performance review

Review the current change set for scalability risk. Assume it will run against 400,000 orders and
1,400,000 order items with 20 or more concurrent users, not against an empty developer database.

Go through these in order and report findings with file and line references.

## Query behaviour

- Does any new code path dereference a lazy association inside a loop, in a stream, or during
  serialization? Estimate how many statements one request now issues.
- Does any new repository method combine a `join fetch` on a collection with `Pageable`? That
  paginates in memory.
- Does any query filter or sort on a column with no supporting index? Name the index that would
  be needed.
- Does any new query lack a `LIMIT` on a table that grows without bound?

## Transactions and connections

- Is there a network call, file I/O, or long computation inside a `@Transactional` block?
- Are read-only paths marked `readOnly = true`?
- Does the change increase concurrency (more replicas, larger pool, more async work) without
  respecting `max replicas x pool size <= max_connections`?

## Payload

- Did a response grow to include an object graph where a projection would do?
- Is a list endpoint unbounded or missing pagination?

## Data volume assumptions

- Does anything here work only because the developer's database is small? Say which query breaks
  first and roughly at what row count.

## Evidence and regression protection

- Is there a measurement backing any claim of improvement in the change description?
- Is there a test that would fail if the fix were reverted? A performance fix with no test is a
  temporary fix.

## Output format

For each finding: severity (blocking / worth fixing / note), the file and line, what happens under
load, the smallest fix, and the command that would prove it. Do not report style issues. If you
find nothing that matters at scale, say that instead of padding the list.
