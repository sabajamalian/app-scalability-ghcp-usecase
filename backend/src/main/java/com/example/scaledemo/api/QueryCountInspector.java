package com.example.scaledemo.api;

import org.hibernate.resource.jdbc.spi.StatementInspector;

/**
 * Counts the SQL statements issued while handling the current request.
 *
 * <p>This exists purely to make the demo legible. Rather than asking people to
 * read Hibernate's debug log and count lines, every API response reports how
 * many SQL statements it took to produce. That number is the thing scenario 1
 * moves.
 *
 * <p>Hibernate instantiates this class by name (see application.yml), not
 * through Spring, so the counter is held statically. One request is handled on
 * one thread, virtual or platform, so a ThreadLocal is accurate here.
 *
 * <p>Do not copy this into production code as-is. In a real system, use
 * Hibernate's own statistics or an OpenTelemetry JDBC instrumentation instead.
 */
public class QueryCountInspector implements StatementInspector {

    private static final ThreadLocal<int[]> COUNTER = ThreadLocal.withInitial(() -> new int[1]);

    @Override
    public String inspect(String sql) {
        COUNTER.get()[0]++;
        return sql;
    }

    public static void reset() {
        COUNTER.get()[0] = 0;
    }

    public static int current() {
        return COUNTER.get()[0];
    }
}
