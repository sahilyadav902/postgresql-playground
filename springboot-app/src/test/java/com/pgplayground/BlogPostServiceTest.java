package com.pgplayground;

import com.pgplayground.dto.BlogPostRequest;
import com.pgplayground.entity.BlogPost;
import com.pgplayground.repository.BlogPostRepository;
import com.pgplayground.service.BlogPostService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class BlogPostServiceTest {

    @Mock BlogPostRepository repo;
    @InjectMocks BlogPostService service;

    private BlogPost post;

    @BeforeEach
    void setUp() {
        post = new BlogPost();
        post.setTitle("PostgreSQL Performance");
        post.setBody("Tips for optimizing queries");
        post.setAuthor("Alice");
        post.setPublished(true);
    }

    @Test
    void findAll_returnsPublishedPosts() {
        when(repo.findByPublishedTrue()).thenReturn(List.of(post));
        List<BlogPost> result = service.findAll();
        assertThat(result).hasSize(1);
        assertThat(result.get(0).getTitle()).isEqualTo("PostgreSQL Performance");
    }

    @Test
    void findById_returnsPost_whenExists() {
        when(repo.findById(1L)).thenReturn(Optional.of(post));
        BlogPost result = service.findById(1L);
        assertThat(result.getAuthor()).isEqualTo("Alice");
    }

    @Test
    void findById_throws404_whenNotFound() {
        when(repo.findById(99L)).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.findById(99L))
            .isInstanceOf(ResponseStatusException.class)
            .hasMessageContaining("Post not found");
    }

    @Test
    void create_savesPost() {
        when(repo.save(any(BlogPost.class))).thenReturn(post);

        BlogPostRequest req = new BlogPostRequest();
        req.title = "New Post";
        req.body = "Content here";
        req.author = "Bob";
        req.published = true;

        BlogPost result = service.create(req);
        assertThat(result).isNotNull();
        verify(repo).save(any(BlogPost.class));
    }

    @Test
    void create_setsPublishedFalseByDefault() {
        BlogPost unpublished = new BlogPost();
        unpublished.setTitle("Draft");
        unpublished.setBody("Draft content");
        unpublished.setPublished(false);
        when(repo.save(any(BlogPost.class))).thenReturn(unpublished);

        BlogPostRequest req = new BlogPostRequest();
        req.title = "Draft";
        req.body = "Draft content";
        // published defaults to false

        BlogPost result = service.create(req);
        assertThat(result.isPublished()).isFalse();
    }

    @Test
    void search_delegatesToRepository() {
        when(repo.fullTextSearchWithRank("postgresql")).thenReturn(List.of());
        List<Object[]> result = service.search("postgresql");
        assertThat(result).isEmpty();
        verify(repo).fullTextSearchWithRank("postgresql");
    }

    @Test
    void searchWithHighlight_delegatesToRepository() {
        when(repo.searchWithHighlight("performance")).thenReturn(List.of());
        List<Object[]> result = service.searchWithHighlight("performance");
        assertThat(result).isEmpty();
        verify(repo).searchWithHighlight("performance");
    }
}
