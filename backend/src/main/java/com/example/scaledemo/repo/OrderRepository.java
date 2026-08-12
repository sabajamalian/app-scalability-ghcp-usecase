package com.example.scaledemo.repo;

import com.example.scaledemo.api.OrderSearchRow;
import com.example.scaledemo.domain.Order;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.OffsetDateTime;
import java.util.List;

public interface OrderRepository extends JpaRepository<Order, Long> {

    /**
     * Scenario 1 entry point.
     *
     * <p>Ordering by primary key on purpose: it uses a backward index scan and is
     * cheap. Scenario 1 is about the number of queries this triggers downstream,
     * not the cost of this one. Keeping this query fast isolates the variable.
     */
    @Query("select o from Order o order by o.id desc")
    List<Order> findRecent(Pageable pageable);

    /**
     * Scenario 2 entry point.
     *
     * <p>Filters on orders.status and orders.placed_at. Neither column is indexed,
     * so PostgreSQL falls back to a sequential scan over the whole table. Run
     * EXPLAIN ANALYZE on it and you will see it.
     *
     * <p>Returns a projection rather than entities so that scenario 2 stays a pure
     * "one slow query" problem with no N+1 mixed in.
     */
    @Query("""
            select new com.example.scaledemo.api.OrderSearchRow(
                o.id, o.orderRef, o.status, o.totalCents, o.placedAt)
            from Order o
            where o.status = :status
              and o.placedAt >= :since
            order by o.placedAt desc
            """)
    List<OrderSearchRow> searchUnindexed(@Param("status") String status,
                                         @Param("since") OffsetDateTime since,
                                         Pageable pageable);
}
