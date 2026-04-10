package com.pgplayground;

import com.pgplayground.dto.OrderRequest;
import com.pgplayground.entity.Order;
import com.pgplayground.entity.Product;
import com.pgplayground.entity.User;
import com.pgplayground.repository.OrderRepository;
import com.pgplayground.repository.ProductRepository;
import com.pgplayground.repository.UserRepository;
import com.pgplayground.service.OrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock OrderRepository orderRepo;
    @Mock UserRepository userRepo;
    @Mock ProductRepository productRepo;
    @InjectMocks OrderService orderService;

    private User alice;
    private Product iphone;
    private Order pendingOrder;

    @BeforeEach
    void setUp() {
        alice = new User();
        alice.setEmail("alice@example.com");
        alice.setUsername("alice");

        iphone = new Product();
        iphone.setSku("SKU-001");
        iphone.setName("iPhone 15");
        iphone.setPrice(new BigDecimal("999.99"));
        iphone.setStock(10);

        pendingOrder = new Order();
        pendingOrder.setUser(alice);
        pendingOrder.setStatus("pending");
        pendingOrder.setTotal(new BigDecimal("999.99"));
    }

    @Test
    void create_buildsOrderWithCorrectTotal() {
        when(userRepo.findById(1L)).thenReturn(Optional.of(alice));
        when(productRepo.findById(1L)).thenReturn(Optional.of(iphone));
        when(productRepo.decrementStock(1L, 2)).thenReturn(1);
        when(orderRepo.save(any(Order.class))).thenAnswer(inv -> inv.getArgument(0));

        OrderRequest req = new OrderRequest();
        req.userId = 1L;
        OrderRequest.OrderItemRequest item = new OrderRequest.OrderItemRequest();
        item.productId = 1L;
        item.quantity = 2;
        req.items = List.of(item);

        Order result = orderService.create(req);
        assertThat(result.getTotal()).isEqualByComparingTo("1999.98");
        assertThat(result.getItems()).hasSize(1);
    }

    @Test
    void create_throwsConflict_whenInsufficientStock() {
        when(userRepo.findById(1L)).thenReturn(Optional.of(alice));
        when(productRepo.findById(1L)).thenReturn(Optional.of(iphone));
        when(productRepo.decrementStock(1L, 100)).thenReturn(0);

        OrderRequest req = new OrderRequest();
        req.userId = 1L;
        OrderRequest.OrderItemRequest item = new OrderRequest.OrderItemRequest();
        item.productId = 1L;
        item.quantity = 100;
        req.items = List.of(item);

        assertThatThrownBy(() -> orderService.create(req))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Insufficient stock");
    }

    @Test
    void updateStatus_allowsValidTransition() {
        when(orderRepo.findById(1L)).thenReturn(Optional.of(pendingOrder));
        when(orderRepo.save(any(Order.class))).thenAnswer(inv -> inv.getArgument(0));

        Order result = orderService.updateStatus(1L, "confirmed");
        assertThat(result.getStatus()).isEqualTo("confirmed");
    }

    @Test
    void updateStatus_throwsUnprocessable_whenCancellingDelivered() {
        pendingOrder.setStatus("delivered");
        when(orderRepo.findById(1L)).thenReturn(Optional.of(pendingOrder));

        assertThatThrownBy(() -> orderService.updateStatus(1L, "cancelled"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Cannot cancel a delivered order");
    }

    @Test
    void updateStatus_throwsUnprocessable_whenUpdatingCancelled() {
        pendingOrder.setStatus("cancelled");
        when(orderRepo.findById(1L)).thenReturn(Optional.of(pendingOrder));

        assertThatThrownBy(() -> orderService.updateStatus(1L, "confirmed"))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Cannot update a cancelled order");
    }

    @Test
    void findById_throws404_whenNotFound() {
        when(orderRepo.findById(99L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> orderService.findById(99L))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Order not found");
    }
}
