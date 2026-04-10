package com.pgplayground.controller;

import com.pgplayground.dto.OrderRequest;
import com.pgplayground.dto.OrderSummary;
import com.pgplayground.entity.Order;
import com.pgplayground.service.OrderService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @GetMapping
    public List<OrderSummary> getAll() {
        return orderService.findAllSummaries();
    }

    @GetMapping("/{id}")
    public Order getById(@PathVariable Long id) {
        return orderService.findById(id);
    }

    @GetMapping("/user/{userId}")
    public List<Order> getByUser(@PathVariable Long userId) {
        return orderService.findByUser(userId);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Order create(@Valid @RequestBody OrderRequest req) {
        return orderService.create(req);
    }

    // Demonstrates status transition validation (mirrors DB trigger logic)
    @PatchMapping("/{id}/status")
    public Order updateStatus(@PathVariable Long id, @RequestParam String status) {
        return orderService.updateStatus(id, status);
    }

    @GetMapping("/revenue-by-status")
    public List<Map<String, Object>> revenueByStatus() {
        return orderService.revenueByStatus().stream()
            .map(row -> Map.of("status", row[0], "revenue", row[1]))
            .toList();
    }
}
