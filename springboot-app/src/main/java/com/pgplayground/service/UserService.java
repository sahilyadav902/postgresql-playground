package com.pgplayground.service;

import com.pgplayground.dto.UserRequest;
import com.pgplayground.entity.User;
import com.pgplayground.repository.UserRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;
import java.util.List;

@Service
@Transactional(readOnly = true)
public class UserService {

    private final UserRepository userRepo;

    public UserService(UserRepository userRepo) {
        this.userRepo = userRepo;
    }

    public List<User> findAll() {
        return userRepo.findAll();
    }

    public User findById(Long id) {
        return userRepo.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "User not found: " + id));
    }

    public List<User> findUsersWithNoOrders() {
        return userRepo.findUsersWithNoOrders();
    }

    @Transactional
    public User create(UserRequest req) {
        if (userRepo.existsByEmail(req.email))
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Email already exists");
        if (userRepo.existsByUsername(req.username))
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Username already exists");

        User user = new User();
        user.setEmail(req.email);
        user.setUsername(req.username);
        user.setDisplayName(req.displayName);
        user.setPhone(req.phone);
        user.setRole(req.role);
        return userRepo.save(user);
    }

    @Transactional
    public User update(Long id, UserRequest req) {
        User user = findById(id);
        user.setDisplayName(req.displayName);
        user.setPhone(req.phone);
        return userRepo.save(user);
    }

    @Transactional
    public void deactivate(Long id) {
        User user = findById(id);
        user.setActive(false);
        userRepo.save(user);
    }

    @Transactional
    public int addLoyaltyPoints(Long id, int points) {
        findById(id); // validate exists
        return userRepo.addLoyaltyPoints(id, points);
    }
}
