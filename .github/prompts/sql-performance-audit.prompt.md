# Repository-wide SQL performance audit

Review every SQL script listed below. Use the `postgres` MCP server for database facts and query
plans. The database is seeded with the repository's representative data volume.

SQL scripts in scope:

{{SQL_FILES}}

## Rules

- Read every listed file and account for it in the report, including test SQL and role/setup SQL.
- Treat source inspection as a hypothesis. A performance finding requires evidence from the
  Postgres MCP server, such as `EXPLAIN (ANALYZE, BUFFERS)`, catalog data, table statistics, or
  `pg_stat_statements`.
- Use plain `EXPLAIN` before `EXPLAIN ANALYZE`. Do not execute statements that mutate data,
  schema, roles, or permissions. The database role is read-only and must not be elevated.
- Evaluate applicable statements for plan shape, row-estimate accuracy, scans, sorts, indexes,
  joins, unbounded reads, locking risk, transaction safety, idempotency, migration conventions,
  seed efficiency, and PostgreSQL best practices.
- Do not claim measured improvement without before and after evidence. Do not recommend an index
  without a plan. If a statement cannot safely be measured, put it in `Statements Not Measured`
  and give the exact reason and verification command.
- Report deliberate teaching defects as findings when evidence confirms them. Do not silently fix
  files and do not pad the report with style-only comments.
- Use repository-relative paths and 1-based line numbers. Use `none` when a table has no rows.
- Return only the Markdown report. Do not wrap it in a code fence or add text before or after it.

## Required output

Use these headings exactly and in this order. Keep every table column, even when it contains
`none`. Severity values are `blocking`, `worth fixing`, or `note`. Evidence status values are
`measured`, `catalog`, `static only`, or `not applicable`.

# SQL Performance and Best-Practices Report

## Run Metadata

| Field | Value |
| --- | --- |
| SQL files reviewed | number |
| Database | PostgreSQL version returned by MCP |
| Data scale | relevant measured row counts |
| Evidence boundary | read-only role and statement timeout |

## SQL Inventory

| File | Purpose | Statements | Evidence status |
| --- | --- | ---: | --- |
| repository-relative path | concise purpose | count | allowed status |

## Findings

| ID | Severity | File:line | Category | Finding | Evidence | Smallest fix | Verification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SQL-001 | allowed severity | path:line | category | load impact | measured fact or static limitation | action or none | exact command |

Sort findings by severity, then file and line. If there are no findings, include one row with
`none` in every cell except Finding, which must say `No actionable findings`.

## Per-File Evidence

Create one `### path/to/file.sql` subsection for every inventory row, in inventory order. Under
each subsection include these labels exactly:

- `Purpose:`
- `Checks performed:`
- `MCP evidence:`
- `Assessment:`

Quote only the decisive plan or catalog lines. State `Not applicable` when runtime database
evidence cannot apply to that kind of script.

## Statements Not Measured

| File:line | Statement | Reason | Safe verification command |
| --- | --- | --- | --- |

Use one row per relevant unmeasured statement. If none, include a single `none` row.

## Recommended Next Actions

Use a numbered list ordered by risk and expected benefit. Every action must refer to a finding ID
and include the command or measurement that proves whether it worked. If no action is needed,
write `1. None.`