-- Extensions the demo depends on.
--
-- pg_stat_statements: aggregates query execution statistics. This is how Copilot
--   (through the Postgres MCP server) finds the N+1 signature in scenario 1:
--   a query with a very high `calls` count and a very low `mean_exec_time`.
--
-- hypopg: creates hypothetical indexes that the planner will consider but that
--   are never actually built. This is how Copilot proves an index will help in
--   scenario 2 *before* anyone writes a migration.
--
-- Note: pg_stat_statements also requires shared_preload_libraries, which is set
-- via the postgres command line in docker-compose.yml.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS hypopg;
