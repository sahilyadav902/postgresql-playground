package com.pgplayground.repository;

import com.pgplayground.entity.Product;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

public interface ProductRepository extends JpaRepository<Product, Long> {

    Optional<Product> findBySku(String sku);
    boolean existsBySku(String sku);

    // Pagination + filtering
    Page<Product> findByActiveTrueAndPriceBetween(BigDecimal min, BigDecimal max, Pageable pageable);
    List<Product> findByCategoryIdAndActiveTrue(Long categoryId);

    // Full-text search using PostgreSQL tsvector
    @Query(value = """
        SELECT * FROM products
        WHERE to_tsvector('english', name || ' ' || COALESCE(description, ''))
              @@ plainto_tsquery('english', :query)
          AND is_active = true
        ORDER BY ts_rank(to_tsvector('english', name || ' ' || COALESCE(description,'')),
                         plainto_tsquery('english', :query)) DESC
        """, nativeQuery = true)
    List<Product> fullTextSearch(@Param("query") String query);

    // Atomic stock decrement (prevents overselling)
    @Modifying
    @Query(value = """
        UPDATE products SET stock = stock - :qty
        WHERE id = :id AND stock >= :qty
        """, nativeQuery = true)
    int decrementStock(@Param("id") Long id, @Param("qty") int qty);

    // Top selling products via join
    @Query(value = """
        SELECT p.*, COALESCE(SUM(oi.quantity), 0) AS total_sold
        FROM products p
        LEFT JOIN order_items oi ON oi.product_id = p.id
        LEFT JOIN orders o ON o.id = oi.order_id AND o.status != 'cancelled'
        GROUP BY p.id
        ORDER BY total_sold DESC
        LIMIT :limit
        """, nativeQuery = true)
    List<Object[]> findTopSellingProducts(@Param("limit") int limit);
}
