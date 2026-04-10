package com.pgplayground.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import java.math.BigDecimal;

public class ProductRequest {
    @NotBlank              public String sku;
    @NotBlank              public String name;
                           public String description;
    @DecimalMin("0.01")    public BigDecimal price;
    @Min(0)                public int stock;
                           public Long categoryId;
}
