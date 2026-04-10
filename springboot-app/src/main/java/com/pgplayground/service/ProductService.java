package com.pgplayground.service;

import com.pgplayground.dto.ProductRequest;
import com.pgplayground.entity.Product;
import com.pgplayground.repository.CategoryRepository;
import com.pgplayground.repository.ProductRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import java.math.BigDecimal;
import java.util.List;

@Service
@Transactional(readOnly = true)
public class ProductService {

    private final ProductRepository productRepo;
    private final CategoryRepository categoryRepo;

    public ProductService(ProductRepository productRepo, CategoryRepository categoryRepo) {
        this.productRepo = productRepo;
        this.categoryRepo = categoryRepo;
    }

    public Page<Product> findAll(Pageable pageable) {
        return productRepo.findAll(pageable);
    }

    public Product findById(Long id) {
        return productRepo.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Product not found: " + id));
    }

    public List<Product> search(String query) {
        return productRepo.fullTextSearch(query);
    }

    public Page<Product> findByPriceRange(BigDecimal min, BigDecimal max, Pageable pageable) {
        return productRepo.findByActiveTrueAndPriceBetween(min, max, pageable);
    }

    @Transactional
    public Product create(ProductRequest req) {
        if (productRepo.existsBySku(req.sku))
            throw new ResponseStatusException(HttpStatus.CONFLICT, "SKU already exists: " + req.sku);

        Product p = new Product();
        p.setSku(req.sku);
        p.setName(req.name);
        p.setDescription(req.description);
        p.setPrice(req.price);
        p.setStock(req.stock);
        if (req.categoryId != null)
            p.setCategory(categoryRepo.findById(req.categoryId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST, "Category not found")));
        return productRepo.save(p);
    }

    @Transactional
    public Product update(Long id, ProductRequest req) {
        Product p = findById(id);
        p.setName(req.name);
        p.setDescription(req.description);
        p.setPrice(req.price);
        p.setStock(req.stock);
        if (req.categoryId != null)
            p.setCategory(categoryRepo.findById(req.categoryId).orElse(null));
        return productRepo.save(p);
    }

    @Transactional
    public void delete(Long id) {
        productRepo.delete(findById(id));
    }

    // Demonstrates atomic stock decrement (prevents overselling)
    @Transactional
    public boolean decrementStock(Long id, int qty) {
        int updated = productRepo.decrementStock(id, qty);
        if (updated == 0)
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Insufficient stock for product: " + id);
        return true;
    }
}
