package com.pgplayground.controller;

import com.pgplayground.dto.UserRequest;
import com.pgplayground.entity.User;
import com.pgplayground.service.UserService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/users")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping
    public List<User> getAll() {
        return userService.findAll();
    }

    @GetMapping("/{id}")
    public User getById(@PathVariable Long id) {
        return userService.findById(id);
    }

    @GetMapping("/no-orders")
    public List<User> getUsersWithNoOrders() {
        return userService.findUsersWithNoOrders();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public User create(@Valid @RequestBody UserRequest req) {
        return userService.create(req);
    }

    @PutMapping("/{id}")
    public User update(@PathVariable Long id, @Valid @RequestBody UserRequest req) {
        return userService.update(id, req);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deactivate(@PathVariable Long id) {
        userService.deactivate(id);
    }

    @PostMapping("/{id}/loyalty-points")
    public Map<String, Object> addLoyaltyPoints(@PathVariable Long id,
                                                 @RequestParam int points) {
        int updated = userService.addLoyaltyPoints(id, points);
        return Map.of("updated", updated, "pointsAdded", points);
    }
}
