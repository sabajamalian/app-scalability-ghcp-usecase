package com.example.scaledemo.api;

import java.util.List;

/**
 * Envelope returned by both demo endpoints.
 *
 * <p>{@code sqlQueryCount} and {@code serverMillis} are included on purpose. A
 * performance demo that requires you to go read a log to see the problem is a
 * worse demo. Here the evidence arrives with the payload.
 */
public record MeasuredResponse<T>(
        List<T> data,
        int sqlQueryCount,
        long serverMillis) {
}
