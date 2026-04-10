package com.pgplayground.service;

import com.pgplayground.dto.OrderRequest;
import com.pgplayground.dto.OrderSummary;
import com.pgplayground.entity.Order;
import com.pgplayground.entity.OrderItem;
import com.pgplayground.entity.Product;
import com.pgplayground.repository.OrderRepository;
import com.pgplayground.repository.ProductRepository;
import com.pgplayground.repository.UserRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import java.math.BigDecimal;
import java.util.List;

@Service
@Transactional(readOnly = true)
public class OrderService {

    private final OrderRepository orderRepo;
    private final UserRepository userRepo;
    private final ProductRepository productRepo;

    public OrderService(OrderRepository orderRepo, UserRepository userRepo,
                        ProductRepository productRepo) {
        this.orderRepo = orderRepo;
        this.userRepo = userRepo;
        this.productRepo = productRepo;
    }

    public List<OrderSummary> findAllSummaries() {
        return orderRepo.findAllOrderSummaries();
    }

    public Order findById(Long id) {
        return orderRepo.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Order not found: " + id));
    }

    public List<Order> findByUser(Long userId) {
        return orderRepo.findByUserIdWithItems(userId);
    }

    // Atomic transaction: create order + decrement stock in one transaction
    @Transactional
    public Order create(OrderRequest req) {
        Order order = new Order();
        order.setUser(userRepo.findById(req.userId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST, "User not found")));
        order.setNotes(req.notes);

        BigDecimal total = BigDecimal.ZERO;
        for (OrderRequest.OrderItemRequest itemReq : req.items) {
            Product product = productRepo.findById(itemReq.productId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "Product not found: " + itemReq.productId));

            // Atomic stock check + decrement
            int updated = productRepo.decrementStock(product.getId(), itemReq.quantity);
            if (updated == 0)
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Insufficient stock for: " + product.getName());

            OrderItem item = new OrderItem();
            item.setOrder(order);
            item.setProduct(product);
            item.setQuantity(itemReq.quantity);
            item.setUnitPrice(product.getPrice());
            order.getItems().add(item);

            total = total.add(product.getPrice().multiply(BigDecimal.valueOf(itemReq.quantity)));
        }
        order.setTotal(total);
        return orderRepo.save(order);
    }

    // Demonstrates status transition validation
    @Transactional
    public Order updateStatus(Long id, String newStatus) {
        Order order = findById(id);
        validateStatusTransition(order.getStatus(), newStatus);
        order.setStatus(newStatus);
        return orderRepo.save(order);
    }

    private void validateStatusTransition(String current, String next) {
        if ("delivered".equals(current) && "cancelled".equals(next))
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                "Cannot cancel a delivered order");
        if ("cancelled".equals(current))
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                "Cannot update a cancelled order");
    }

    public List<Object[]> revenueByStatus() {
        return orderRepo.revenueByStatus();
    }
}
