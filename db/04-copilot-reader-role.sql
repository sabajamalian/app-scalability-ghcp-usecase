-- The read-only role the MCP server connects as.
--
-- WHY THIS FILE MATTERS MORE THAN IT LOOKS
--
-- Postgres MCP servers advertise a "read-only" or "restricted" access mode.
-- Treat that as a convenience, not a security control: the vendors themselves
-- describe their SQL filtering as best effort. The database role below is the
-- actual boundary. If you take one thing from this repository into your own
-- environment, take this file.
--
-- Credentials here are local-demo-only and are deliberately committed so the
-- demo runs with zero setup. Never do this for a real database.

CREATE ROLE copilot_perf_reader LOGIN PASSWORD 'copilot_demo_readonly';

-- No writes, ever, regardless of what the client asks for.
ALTER ROLE copilot_perf_reader SET default_transaction_read_only = on;

-- A runaway analytical query from an agent should die, not take the demo with
-- it. These are per-role defaults and apply to every session it opens.
ALTER ROLE copilot_perf_reader SET statement_timeout = '15s';
ALTER ROLE copilot_perf_reader SET lock_timeout = '2s';
ALTER ROLE copilot_perf_reader SET idle_in_transaction_session_timeout = '30s';

GRANT CONNECT ON DATABASE scaledemo TO copilot_perf_reader;
GRANT USAGE ON SCHEMA public TO copilot_perf_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO copilot_perf_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO copilot_perf_reader;

-- Explicitly deny object creation. Without this, a role can still create
-- objects in schema public on older PostgreSQL defaults.
REVOKE CREATE ON SCHEMA public FROM copilot_perf_reader;

-- Required to read pg_stat_statements, which is how the N+1 signature in
-- scenario 1 becomes visible (high `calls`, low `mean_exec_time`).
GRANT pg_read_all_stats TO copilot_perf_reader;

-- Required for hypothetical index simulation in scenario 2. hypopg keeps its
-- indexes in per-session memory and writes nothing to disk, so this stays
-- compatible with default_transaction_read_only.
GRANT EXECUTE ON FUNCTION hypopg_create_index(text) TO copilot_perf_reader;
GRANT EXECUTE ON FUNCTION hypopg_reset() TO copilot_perf_reader;
