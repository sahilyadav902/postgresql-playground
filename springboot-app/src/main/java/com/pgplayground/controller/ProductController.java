package com.pgplayground.controller;

import com.pgplayground.dto.ProductRequest;
import com.pgplayground.entity.Product;
import com.pgplayground.service.ProductService;
import jakarta.validation.Valid;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/products")
public class ProductController {

    private final ProductService productService;

    public ProductController(ProductService productService) {
        this.productService = productService;
    }

    @GetMapping
    public Page<Product> getAll(@PageableDefault(size = 20, sort = "name") Pageable pageable) {
        return productService.findAll(pageable);
    }

    @GetMapping("/{id}")
    public Product getById(@PathVariable Long id) {
        return productService.findById(id);
    }

    @GetMapping("/search")
    public List<Product> search(@RequestParam String q) {
        return productService.search(q);
    }

    @GetMapping("/price-range")
    public Page<Product> byPriceRange(@RequestParam BigDecimal min,
                                       @RequestParam BigDecimal max,
                                       Pageable pageable) {
        return productService.findByPriceRange(min, max, pageable);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Product create(@Valid @RequestBody ProductRequest req) {
        return productService.create(req);
    }

    @PutMapping("/{id}")
    public Product update(@PathVariable Long id, @Valid @RequestBody ProductRequest req) {
        return productService.update(id, req);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        productService.delete(id);
    }

    // Demonstrates atomic stock decrement
    @PostMapping("/{id}/decrement-stock")
    public Map<String, Object> decrementStock(@PathVariable Long id, @RequestParam int qty) {
        productService.decrementStock(id, qty);
        return Map.of("productId", id, "decremented", qty);
    }
}
