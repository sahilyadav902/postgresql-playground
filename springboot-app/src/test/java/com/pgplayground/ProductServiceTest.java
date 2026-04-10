package com.pgplayground;

import com.pgplayground.dto.ProductRequest;
import com.pgplayground.entity.Product;
import com.pgplayground.repository.CategoryRepository;
import com.pgplayground.repository.ProductRepository;
import com.pgplayground.service.ProductService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ProductServiceTest {

    @Mock ProductRepository productRepo;
    @Mock CategoryRepository categoryRepo;
    @InjectMocks ProductService productService;

    private Product iphone;

    @BeforeEach
    void setUp() {
        iphone = new Product();
        iphone.setSku("SKU-001");
        iphone.setName("iPhone 15");
        iphone.setPrice(new BigDecimal("999.99"));
        iphone.setStock(50);
    }

    @Test
    void findById_returnsProduct_whenExists() {
        when(productRepo.findById(1L)).thenReturn(Optional.of(iphone));
        Product result = productService.findById(1L);
        assertThat(result.getSku()).isEqualTo("SKU-001");
    }

    @Test
    void findById_throws404_whenNotFound() {
        when(productRepo.findById(99L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> productService.findById(99L))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Product not found");
    }

    @Test
    void create_savesProduct_whenSkuUnique() {
        when(productRepo.existsBySku("SKU-NEW")).thenReturn(false);
        when(productRepo.save(any(Product.class))).thenReturn(iphone);

        ProductRequest req = new ProductRequest();
        req.sku = "SKU-NEW";
        req.name = "New Product";
        req.price = new BigDecimal("49.99");
        req.stock = 10;

        Product result = productService.create(req);
        assertThat(result).isNotNull();
        verify(productRepo).save(any(Product.class));
    }

    @Test
    void create_throwsConflict_whenSkuExists() {
        when(productRepo.existsBySku("SKU-001")).thenReturn(true);

        ProductRequest req = new ProductRequest();
        req.sku = "SKU-001";
        req.name = "Duplicate";
        req.price = BigDecimal.TEN;

        assertThatThrownBy(() -> productService.create(req))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("SKU already exists");
        verify(productRepo, never()).save(any());
    }

    @Test
    void decrementStock_returnsTrue_whenStockSufficient() {
        when(productRepo.decrementStock(1L, 5)).thenReturn(1);
        boolean result = productService.decrementStock(1L, 5);
        assertThat(result).isTrue();
    }

    @Test
    void decrementStock_throwsConflict_whenInsufficientStock() {
        when(productRepo.decrementStock(1L, 100)).thenReturn(0);
        assertThatThrownBy(() -> productService.decrementStock(1L, 100))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Insufficient stock");
    }

    @Test
    void findAll_returnsPaginatedResults() {
        Page<Product> page = new PageImpl<>(List.of(iphone));
        when(productRepo.findAll(any(Pageable.class))).thenReturn(page);

        Page<Product> result = productService.findAll(Pageable.unpaged());
        assertThat(result.getContent()).hasSize(1);
    }

    @Test
    void delete_callsRepositoryDelete() {
        when(productRepo.findById(1L)).thenReturn(Optional.of(iphone));
        productService.delete(1L);
        verify(productRepo).delete(iphone);
    }
}
