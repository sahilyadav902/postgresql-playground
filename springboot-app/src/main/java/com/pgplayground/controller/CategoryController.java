package com.pgplayground.controller;

import com.pgplayground.repository.CategoryRepository;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/categories")
public class CategoryController {

    private final CategoryRepository categoryRepo;

    public CategoryController(CategoryRepository categoryRepo) {
        this.categoryRepo = categoryRepo;
    }

    @GetMapping
    public List<?> getAll() {
        return categoryRepo.findAll();
    }

    @GetMapping("/tree")
    public List<Map<String, Object>> getTree() {
        return categoryRepo.findCategoryTree().stream()
            .map(row -> Map.of(
                "id",       row[0],
                "name",     row[1],
                "parentId", row[2] == null ? "" : row[2],
                "path",     row[3],
                "depth",    row[4]
            )).toList();
    }

    @GetMapping("/top-level")
    public List<?> getTopLevel() {
        return categoryRepo.findByParentIsNull();
    }
}
