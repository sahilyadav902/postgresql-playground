package com.pgplayground.service;

import com.pgplayground.dto.BlogPostRequest;
import com.pgplayground.entity.BlogPost;
import com.pgplayground.repository.BlogPostRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import java.util.List;

@Service
@Transactional(readOnly = true)
public class BlogPostService {

    private final BlogPostRepository repo;

    public BlogPostService(BlogPostRepository repo) {
        this.repo = repo;
    }

    public List<BlogPost> findAll() {
        return repo.findByPublishedTrue();
    }

    public BlogPost findById(Long id) {
        return repo.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Post not found: " + id));
    }

    public List<Object[]> search(String query) {
        return repo.fullTextSearchWithRank(query);
    }

    public List<Object[]> searchWithHighlight(String query) {
        return repo.searchWithHighlight(query);
    }

    @Transactional
    public BlogPost create(BlogPostRequest req) {
        BlogPost post = new BlogPost();
        post.setTitle(req.title);
        post.setBody(req.body);
        post.setAuthor(req.author);
        post.setPublished(req.published);
        return repo.save(post);
    }
}
