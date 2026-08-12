package com.example.scaledemo.api;

import java.time.OffsetDateTime;
import java.util.List;

/** One row of the order listing returned by {@code GET /api/orders}. */
public record OrderSummary(
        Long id,
        String orderRef,
        String status,
        long totalCents,
        OffsetDateTime placedAt,
        String customerName,
        String customerEmail,
        List<OrderLine> lines) {
}
