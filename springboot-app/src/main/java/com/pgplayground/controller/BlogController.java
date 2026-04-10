package com.pgplayground.controller;

import com.pgplayground.dto.BlogPostRequest;
import com.pgplayground.entity.BlogPost;
import com.pgplayground.service.BlogPostService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/blog")
public class BlogController {

    private final BlogPostService service;

    public BlogController(BlogPostService service) {
        this.service = service;
    }

    @GetMapping
    public List<BlogPost> getAll() {
        return service.findAll();
    }

    @GetMapping("/{id}")
    public BlogPost getById(@PathVariable Long id) {
        return service.findById(id);
    }

    // Full-text search with TS_RANK
    @GetMapping("/search")
    public List<Map<String, Object>> search(@RequestParam String q) {
        return service.search(q).stream()
            .map(row -> Map.of(
                "id",     row[0],
                "title",  row[1],
                "body",   row[2],
                "author", row[3] == null ? "" : row[3],
                "rank",   row[8]
            )).toList();
    }

    // Full-text search with TS_HEADLINE snippets
    @GetMapping("/search/highlight")
    public List<Map<String, Object>> searchWithHighlight(@RequestParam String q) {
        return service.searchWithHighlight(q).stream()
            .map(row -> Map.of(
                "id",      row[0],
                "title",   row[1],
                "snippet", row[2],
                "rank",    row[3]
            )).toList();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public BlogPost create(@Valid @RequestBody BlogPostRequest req) {
        return service.create(req);
    }
}
