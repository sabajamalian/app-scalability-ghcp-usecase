package com.example.scaledemo;

import com.example.scaledemo.api.QueryCountInspector;
import com.example.scaledemo.service.OrderService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The regression gate for demo scenario 1.
 *
 * <p>A performance fix that no test protects is a temporary fix. This test
 * asserts a bound on how many SQL statements one request issues, so a future
 * refactor that reintroduces lazy-loading amplification fails CI instead of
 * quietly shipping.
 *
 * <p>It asserts a bound rather than an exact number on purpose. Pinning the
 * count to exactly 4 would make the test fail for a harmless extra statement,
 * and a flaky performance test gets deleted rather than fixed.
 *
 * <p>Before the fix this test FAILS (the endpoint issues 219 statements). That
 * is the intended starting state of the demo, and it is why
 * .github/workflows/perf-gate.yml runs on pull_request and workflow_dispatch
 * only, never on push to the default branch.
 */
@SpringBootTest
@Testcontainers
@DisplayName("GET /api/orders must not amplify into per-row queries")
class OrderQueryCountTest {

    private static final int MAX_STATEMENTS_PER_REQUEST = 10;
    private static final int PAGE_SIZE = 50;

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:17-alpine");

    @Autowired
    private OrderService orderService;

    @Test
    void listingOrdersIssuesABoundedNumberOfStatements() {
        // Warm up so first-touch metadata queries are not counted as amplification.
        orderService.listRecentOrders(PAGE_SIZE);

        QueryCountInspector.reset();
        var orders = orderService.listRecentOrders(PAGE_SIZE);
        int statements = QueryCountInspector.current();

        assertThat(orders).isNotEmpty();

        assertThat(statements)
                .as("""
                        GET /api/orders issued %d SQL statements for %d orders.

                        This is query amplification: a lazy association is being dereferenced
                        per row. The statement count must not scale with the number of rows
                        returned.

                        Reproduce it locally with:
                            make up && make measure-1

                        See docs/01-scenario-n-plus-one.md.
                        """.formatted(statements, orders.size()))
                .isLessThanOrEqualTo(MAX_STATEMENTS_PER_REQUEST);
    }

    @Test
    void orderSearchIssuesExactlyOneStatement() {
        orderService.searchOrders("SHIPPED", 48, PAGE_SIZE);

        QueryCountInspector.reset();
        orderService.searchOrders("SHIPPED", 48, PAGE_SIZE);

        assertThat(QueryCountInspector.current())
                .as("Order search uses a DTO projection and must stay at a single statement")
                .isEqualTo(1);
    }
}
