# 04. Instructions are advisory. CI is enforcement.

**Time: about 3 minutes.**

This repository ships a fairly complete set of Copilot customization: a repo-wide
`copilot-instructions.md`, three path-scoped instruction files, three prompt files, and a custom
agent. They are genuinely useful. They raise the floor on every answer you get.

They are also not a control.

## What instruction files actually do

They are text prepended to the model's context. That is the whole mechanism.

This means:

- A model can ignore them. Not maliciously, just because attention is finite and the instruction
  competed with everything else in context.
- They apply only when the relevant file is in scope. `applyTo: "backend/**"` does nothing when
  someone is editing a migration.
- They do not apply to a teammate who is not using Copilot, or who is using a different tool.
- They cannot fail a build.

Watch this happen live: `.github/instructions/java-backend.instructions.md` explicitly rules out
`FetchType.EAGER` and explicitly warns about `join fetch` plus `Pageable`. Run the scenario 1
prompt a few times. You will sometimes get one of those suggestions anyway. That is not a defect
in the instructions; it is what "advisory" means.

## What the CI gate does

`.github/workflows/perf-gate.yml` runs `OrderQueryCountTest`, which asserts a bound on the number
of SQL statements one request issues.

```bash
make test
```

Before the fix:

```
[ERROR] OrderQueryCountTest.listingOrdersIssuesABoundedNumberOfStatements:72
GET /api/orders issued 121 SQL statements for 40 orders.

This is query amplification: a lazy association is being dereferenced
per row. The statement count must not scale with the number of rows
returned.

Reproduce it locally with:
    make up && make measure-1

See docs/01-scenario-n-plus-one.md.

Expecting actual:
  121
to be less than or equal to:
  10
```

(The test uses a 40-row fixture, so the count is 121 rather than the 219 you see against the
seeded database. The point is that it scales with row count, which is exactly what the assertion
forbids.)

That failure message cannot be reasoned with, cannot be forgotten during review, and applies to
every contributor regardless of what tooling they use.

## The division of labour

| | Instructions and prompts | CI gate |
| --- | --- | --- |
| Mechanism | Text in context | Test that fails a build |
| Applies to | People using Copilot | Everyone |
| Can be ignored | Yes | No |
| Good at | Raising the quality of every answer | Preventing one specific regression |
| Cost to add | Minutes | Hours, plus maintenance |

Use both. Instructions make good outcomes more likely across the board. CI makes specific bad
outcomes impossible. Neither substitutes for the other, and a team that ships only the first half
has documentation, not a guardrail.

## Design notes on this workflow

**It runs on `pull_request` and `workflow_dispatch` only, never on push to `main`.** This repo
ships with the defects still in place, so the gate is *supposed* to fail on a clean clone. Running
it on the default branch would leave a public demo repo permanently red, which teaches the wrong
lesson. In your own repository, once the fixes are in, add `push: branches: [main]`.

**The assertion is a bound, not an exact number.** `<= 10`, not `== 4`. An exact assertion breaks
when someone adds one harmless statement, and a flaky performance test gets deleted rather than
fixed. Pick a budget with headroom, and make the failure message explain the reasoning.

**Testcontainers, not H2.** The test starts real PostgreSQL 17. An in-memory database with
different query planning would let real regressions through while failing on differences that do
not matter.

**The k6 job is manual only.** Load tests are slow and noisy on shared runners; percentile
thresholds on a shared CI runner produce false failures. Statement counts are deterministic and
make a much better blocking gate. Run the load test on demand, or nightly against a stable
environment, and keep the deterministic check on every pull request.

## What else is worth gating

Statement count is the easiest high-value gate to add, but the same pattern applies to:

- **Payload size.** Assert a response is under N kilobytes. Catches the object-graph-leak version
  of the same problem.
- **Index presence.** Assert that a migration exists for any query filtering on a large table.
- **Query plan shape.** Assert that a critical query's plan contains `Index Scan` and not
  `Seq Scan`. Brittle, but powerful for a handful of endpoints that must not regress.
- **Pool configuration.** Assert `max replicas x pool size <= max_connections`, evaluated from
  the deployment manifest.

Each is a few lines of test code, and each converts a piece of tribal knowledge into something
that survives staff turnover.

---

Next: [05. Adopting this in your own application](05-adopt-in-your-app.md)
