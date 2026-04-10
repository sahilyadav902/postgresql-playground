package com.pgplayground.repository;

import com.pgplayground.entity.Category;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import java.util.List;
import java.util.Optional;

public interface CategoryRepository extends JpaRepository<Category, Long> {

    Optional<Category> findByName(String name);

    // Self-join: all top-level categories
    List<Category> findByParentIsNull();

    // All subcategories of a parent
    List<Category> findByParentId(Long parentId);

    // Recursive CTE via native query — full category tree
    @Query(value = """
        WITH RECURSIVE tree AS (
            SELECT id, name, parent_id, name::TEXT AS path, 0 AS depth
            FROM categories WHERE parent_id IS NULL
            UNION ALL
            SELECT c.id, c.name, c.parent_id,
                   (t.path || ' > ' || c.name)::TEXT, t.depth + 1
            FROM categories c JOIN tree t ON t.id = c.parent_id
        )
        SELECT id, name, parent_id, path, depth FROM tree ORDER BY path
        """, nativeQuery = true)
    List<Object[]> findCategoryTree();
}
