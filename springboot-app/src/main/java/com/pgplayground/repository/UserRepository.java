package com.pgplayground.repository;

import com.pgplayground.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.List;
import java.util.Optional;

public interface UserRepository extends JpaRepository<User, Long> {

    Optional<User> findByEmail(String email);
    Optional<User> findByUsername(String username);
    boolean existsByEmail(String email);
    boolean existsByUsername(String username);

    List<User> findByActiveTrue();
    List<User> findByRole(String role);

    // JPQL join fetch to avoid N+1
    @Query("SELECT u FROM User u WHERE u.active = true ORDER BY u.createdAt DESC")
    List<User> findAllActiveUsers();

    // Native query: users with no orders (anti-join)
    @Query(value = """
        SELECT u.* FROM users u
        WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id)
        """, nativeQuery = true)
    List<User> findUsersWithNoOrders();

    // Bulk update loyalty points
    @Modifying
    @Query("UPDATE User u SET u.loyaltyPoints = u.loyaltyPoints + :points WHERE u.id = :id")
    int addLoyaltyPoints(@Param("id") Long id, @Param("points") int points);
}
