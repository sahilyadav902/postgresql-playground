package com.pgplayground.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public class UserRequest {
    @Email @NotBlank public String email;
    @NotBlank        public String username;
                     public String displayName;
                     public String phone;
                     public String role = "customer";
}
