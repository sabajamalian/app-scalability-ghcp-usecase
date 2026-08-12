package com.example.scaledemo.api;

import com.example.scaledemo.service.OrderService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    /** Scenario 1: order listing. Watch {@code sqlQueryCount} in the response. */
    @GetMapping
    public MeasuredResponse<OrderSummary> listOrders(
            @RequestParam(defaultValue = "50") int limit) {

        QueryCountInspector.reset();
        long start = System.nanoTime();
        List<OrderSummary> orders = orderService.listRecentOrders(clamp(limit));
        long elapsedMillis = (System.nanoTime() - start) / 1_000_000;

        return new MeasuredResponse<>(orders, QueryCountInspector.current(), elapsedMillis);
    }

    /** Scenario 2: order search. Watch {@code serverMillis}, not the query count. */
    @GetMapping("/search")
    public MeasuredResponse<OrderSearchRow> searchOrders(
            @RequestParam(defaultValue = "SHIPPED") String status,
            @RequestParam(defaultValue = "48") int withinHours,
            @RequestParam(defaultValue = "50") int limit) {

        QueryCountInspector.reset();
        long start = System.nanoTime();
        List<OrderSearchRow> rows = orderService.searchOrders(status, withinHours, clamp(limit));
        long elapsedMillis = (System.nanoTime() - start) / 1_000_000;

        return new MeasuredResponse<>(rows, QueryCountInspector.current(), elapsedMillis);
    }

    private static int clamp(int limit) {
        return Math.max(1, Math.min(limit, 200));
    }
}
