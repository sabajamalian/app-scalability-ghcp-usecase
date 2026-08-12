# PostgreSQL plus hypopg.
#
# hypopg is not in the official postgres image. It is required for scenario 2,
# where Copilot simulates a candidate index and re-runs EXPLAIN *before* anyone
# writes a migration. That "prove it first" step is the most persuasive part of
# the demo, so it is worth the extra build layer.
#
# pg_stat_statements ships with the postgres image already but must be loaded
# via shared_preload_libraries, which is set in docker-compose.yml.

FROM postgres:17-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-17-hypopg \
    && rm -rf /var/lib/apt/lists/*
