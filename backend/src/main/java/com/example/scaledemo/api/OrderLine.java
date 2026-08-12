package com.example.scaledemo.api;

/** One line item inside an {@link OrderSummary}. */
public record OrderLine(
        Long id,
        String productName,
        String productSku,
        int quantity,
        int unitPriceCents) {
}
