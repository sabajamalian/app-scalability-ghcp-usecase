package com.example.scaledemo.service;

import com.example.scaledemo.api.OrderLine;
import com.example.scaledemo.api.OrderSearchRow;
import com.example.scaledemo.api.OrderSummary;
import com.example.scaledemo.domain.Order;
import com.example.scaledemo.repo.OrderRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;

@Service
public class OrderService {

    private final OrderRepository orderRepository;

    public OrderService(OrderRepository orderRepository) {
        this.orderRepository = orderRepository;
    }

    /**
     * Returns the most recent orders with their customer and line items.
     *
     * <p>This method is the subject of demo scenario 1. It looks completely
     * ordinary, which is the point: this shape ships to production constantly.
     *
     * <p>Read it again with an eye on how many SQL statements it causes. The
     * repository call is one query. Every {@code getCustomer()}, every
     * {@code getItems()}, and every {@code getProduct()} below dereferences a lazy
     * association, and each of those is another round trip to PostgreSQL.
     *
     * <p>Do not fix this by hand. Let Copilot find it, then compare what it says
     * with code context alone against what it says once it can read
     * pg_stat_statements through MCP. That contrast is the demo.
     */
    @Transactional(readOnly = true)
    public List<OrderSummary> listRecentOrders(int limit) {
        List<Order> orders = orderRepository.findRecent(PageRequest.of(0, limit));

        return orders.stream()
                .map(order -> new OrderSummary(
                        order.getId(),
                        order.getOrderRef(),
                        order.getStatus(),
                        order.getTotalCents(),
                        order.getPlacedAt(),
                        order.getCustomer().getFullName(),
                        order.getCustomer().getEmail(),
                        order.getItems().stream()
                                .map(item -> new OrderLine(
                                        item.getId(),
                                        item.getProduct().getName(),
                                        item.getProduct().getSku(),
                                        item.getQuantity(),
                                        item.getUnitPriceCents()))
                                .toList()))
                .toList();
    }

    /**
     * Searches orders by status within a recent time window.
     *
     * <p>This method is the subject of demo scenario 2. It issues exactly one SQL
     * statement, so there is nothing wrong with the Java. The problem is in the
     * database, and you cannot see it by reading this file. That is precisely why
     * the scenario needs EXPLAIN rather than code review.
     */
    @Transactional(readOnly = true)
    public List<OrderSearchRow> searchOrders(String status, int withinHours, int limit) {
        OffsetDateTime since = OffsetDateTime.now().minusHours(withinHours);
        return orderRepository.searchUnindexed(status, since, PageRequest.of(0, limit));
    }
}
