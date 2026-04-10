package com.pgplayground.entity;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(name = "page_views")
public class PageView {

    @Id
    @Column(name = "page", nullable = false)
    private String page;

    @Column(name = "view_date", nullable = false)
    private java.time.LocalDate viewDate;

    @Column(name = "view_count", nullable = false)
    private long viewCount = 0;

    // Composite PK handled via @IdClass or @EmbeddedId — using native queries instead
    // This entity is used only for reference; UPSERT done via native query

    public String getPage() { return page; }
    public void setPage(String page) { this.page = page; }
    public java.time.LocalDate getViewDate() { return viewDate; }
    public void setViewDate(java.time.LocalDate viewDate) { this.viewDate = viewDate; }
    public long getViewCount() { return viewCount; }
    public void setViewCount(long viewCount) { this.viewCount = viewCount; }
}
