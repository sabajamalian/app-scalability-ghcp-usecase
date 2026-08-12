package com.example.scaledemo.api;

import java.time.OffsetDateTime;

/**
 * Flat projection returned by {@code GET /api/orders/search}.
 *
 * <p>Constructed directly by a JPQL constructor expression, so this endpoint
 * issues exactly one SQL statement. Scenario 2 is about that statement being
 * slow, not about how many there are.
 */
public record OrderSearchRow(
        Long id,
        String orderRef,
        String status,
        long totalCents,
        OffsetDateTime placedAt) {
}
