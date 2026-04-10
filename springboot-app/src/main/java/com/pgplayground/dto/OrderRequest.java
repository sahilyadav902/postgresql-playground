package com.pgplayground.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import java.util.List;

public class OrderRequest {
    @NotNull public Long userId;
             public String notes;
    @NotNull public List<OrderItemRequest> items;

    public static class OrderItemRequest {
        @NotNull public Long productId;
        @Min(1)  public int quantity;
    }
}
