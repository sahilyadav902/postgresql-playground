package com.pgplayground.repository;

import com.pgplayground.dto.OrderSummary;
import com.pgplayground.entity.Order;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.List;

public interface OrderRepository extends JpaRepository<Order, Long> {

    List<Order> findByUserId(Long userId);
    List<Order> findByStatus(String status);

    // JPQL projection into DTO — demonstrates multi-table join + aggregation
    @Query("""
        SELECT new com.pgplayground.dto.OrderSummary(
            o.id, u.username, u.email, o.status, o.total,
            COUNT(oi.id), o.createdAt
        )
        FROM Order o
        JOIN o.user u
        JOIN o.items oi
        GROUP BY o.id, u.username, u.email, o.status, o.total, o.createdAt
        ORDER BY o.createdAt DESC
        """)
    List<OrderSummary> findAllOrderSummaries();

    // Orders for a specific user with items eagerly loaded
    @Query("SELECT DISTINCT o FROM Order o JOIN FETCH o.items i JOIN FETCH i.product WHERE o.user.id = :userId")
    List<Order> findByUserIdWithItems(@Param("userId") Long userId);

    // Revenue by status
    @Query("SELECT o.status, SUM(o.total) FROM Order o GROUP BY o.status")
    List<Object[]> revenueByStatus();
}
