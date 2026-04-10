package com.pgplayground.dto;

import java.math.BigDecimal;
import java.time.Instant;

public class OrderSummary {
    public Long orderId;
    public String username;
    public String email;
    public String status;
    public BigDecimal total;
    public long itemCount;
    public Instant createdAt;

    public OrderSummary(Long orderId, String username, String email,
                        String status, BigDecimal total, long itemCount, Instant createdAt) {
        this.orderId = orderId;
        this.username = username;
        this.email = email;
        this.status = status;
        this.total = total;
        this.itemCount = itemCount;
        this.createdAt = createdAt;
    }
}
