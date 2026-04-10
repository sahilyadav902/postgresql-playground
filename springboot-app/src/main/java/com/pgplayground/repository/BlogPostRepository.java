package com.pgplayground.repository;

import com.pgplayground.entity.BlogPost;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.List;

public interface BlogPostRepository extends JpaRepository<BlogPost, Long> {

    List<BlogPost> findByPublishedTrue();

    // Full-text search with ranking using stored tsvector column
    @Query(value = """
        SELECT *, TS_RANK(search_vec, WEBSEARCH_TO_TSQUERY('english', :query)) AS rank
        FROM blog_posts
        WHERE search_vec @@ WEBSEARCH_TO_TSQUERY('english', :query)
          AND published = true
        ORDER BY rank DESC
        """, nativeQuery = true)
    List<Object[]> fullTextSearchWithRank(@Param("query") String query);

    // Full-text search with highlighted snippets
    @Query(value = """
        SELECT id, title,
               TS_HEADLINE('english', body, WEBSEARCH_TO_TSQUERY('english', :query),
                   'MaxWords=20, MinWords=5, StartSel=<mark>, StopSel=</mark>') AS snippet,
               TS_RANK(search_vec, WEBSEARCH_TO_TSQUERY('english', :query)) AS rank
        FROM blog_posts
        WHERE search_vec @@ WEBSEARCH_TO_TSQUERY('english', :query)
          AND published = true
        ORDER BY rank DESC
        """, nativeQuery = true)
    List<Object[]> searchWithHighlight(@Param("query") String query);
}
