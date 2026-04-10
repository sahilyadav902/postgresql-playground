package com.pgplayground.dto;

import jakarta.validation.constraints.NotBlank;

public class BlogPostRequest {
    @NotBlank public String title;
    @NotBlank public String body;
              public String author;
              public boolean published = false;
}
